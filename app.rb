require 'bundler/setup'
Bundler.require
require 'ice_cube'
require 'json'
require 'logger'
require 'set'
require 'time'

EVENTS_PATH = File.join(__dir__, 'webcal_events.json')
STATUS_PATH = File.join(__dir__, 'webcal_status.json')
STALE_AFTER_SECONDS = 15 * 60
MAX_RANGE_DAYS = 31
SSE_HEARTBEAT_SECONDS = 15
MAX_SSE_CLIENTS = 16
WATCH_INTERVAL_SECONDS = 2
NO_TITLE = 'Без названия'.freeze

LOGGER = Logger.new($stdout, level: Logger::INFO)

configure do
  # Allow access from any host name (calendar.internal, LAN IP, localhost)
  set :host_authorization, permitted_hosts: []
  set :bind, '0.0.0.0'
  set :port, Integer(ENV.fetch('APP_PORT', 5000))
  set :server, :puma
  # Each open /updates stream holds a thread (MAX_SSE_CLIENTS at most), so leave room for regular requests
  set :server_settings, Threads: '0:48'
  set :public_folder, File.join(__dir__, 'public')
  # Asset URLs are versioned by mtime, so browsers may cache them indefinitely
  set :static_cache_control, [:public, :immutable, { max_age: 31_536_000 }]
end

# Parsed calendar data, reloaded only when the fetcher replaces the JSON file.
class EventStore
  Event = Struct.new(:uid, :summary, :location, :all_day, :start, :end, :schedule, :excluded_dates,
                     keyword_init: true)
  Snapshot = Struct.new(:events, :updated_at, :mtime, keyword_init: true)

  RANGE_CACHE_SIZE = 32

  def initialize(path)
    @path = path
    @mutex = Mutex.new
    # IceCube schedules keep iteration state, so one expansion runs at a time
    @expand_mutex = Mutex.new
    @snapshot = nil
    @range_cache = {}
  end

  def snapshot
    mtime = File.mtime(@path)
    @mutex.synchronize do
      reload(mtime) unless @snapshot && @snapshot.mtime == mtime
      @snapshot
    end
  rescue Errno::ENOENT
    nil
  end

  # Events grouped by local date ('YYYY-MM-DD' => [event JSON]) for an inclusive date range
  def events_between(from, to)
    snap = snapshot
    return unless snap

    key = [from, to]
    @mutex.synchronize do
      cached = @range_cache[key]
      return cached if cached && cached[:mtime] == snap.mtime
    end

    @expand_mutex.synchronize do
      # Another request may have expanded the same range while this one waited
      cached = @mutex.synchronize { @range_cache[key] }
      return cached if cached && cached[:mtime] == snap.mtime

      result = { mtime: snap.mtime, days: expand(snap.events, from, to) }
      @mutex.synchronize do
        @range_cache.shift if @range_cache.size >= RANGE_CACHE_SIZE
        @range_cache[key] = result
      end
      result
    end
  end

  private

  def reload(mtime)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    data = JSON.parse(File.read(@path, encoding: 'UTF-8'))
    @snapshot = Snapshot.new(events: build_events(data['events'] || []),
                             updated_at: data['updated_at'], mtime: mtime)
    @range_cache.clear
    elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    LOGGER.info("Loaded #{@snapshot.events.size} events in #{elapsed} ms")
  rescue JSON::ParserError, SystemCallError => e
    # Keep serving the previous data (if any) until the next file change
    LOGGER.error("Failed to load #{@path}: #{e.message}")
    @snapshot.mtime = mtime if @snapshot
  end

  def build_events(raw_events)
    # Modified occurrences of a recurring series share the series UID and replace
    # the original occurrence identified by RECURRENCE-ID (or by date when absent)
    recurring_uids = raw_events.select { |raw| raw['rrule'] }.map { |raw| raw['uid'] }.to_set
    overrides = raw_events.select { |raw| !raw['rrule'] && recurring_uids.include?(raw['uid']) }
                          .group_by { |raw| raw['uid'] }

    raw_events.filter_map do |raw|
      build_event(raw, overrides.fetch(raw['uid'], []))
    rescue ArgumentError, TypeError, NoMethodError => e
      LOGGER.warn("Skipping event #{raw['summary'].inspect}: #{e.message}")
      nil
    end
  end

  def build_event(raw, overrides)
    return unless raw['start']

    all_day = raw['all_day'] == true
    start = all_day ? Date.parse(raw['start']) : Time.iso8601(raw['start'])
    finish = raw['end'] && (all_day ? Date.parse(raw['end']) : Time.iso8601(raw['end']))
    finish = start + 1 if all_day && (finish.nil? || finish <= start)
    finish = start + 3600 if !all_day && (finish.nil? || finish < start)

    event = Event.new(uid: raw['uid'].to_s, summary: raw['summary'].to_s.strip, location: raw['location'].to_s,
                      all_day: all_day, start: start, end: finish)
    return event unless raw['rrule']

    first = all_day ? Time.local(start.year, start.month, start.day) : start
    duration = all_day ? (finish - start).to_i * 86_400 : (finish - start).to_i
    event.schedule = IceCube::Schedule.new(first, duration: duration) do |schedule|
      schedule.add_recurrence_rule(IceCube::Rule.from_ical(raw['rrule']))
    end
    excluded = Array(raw['exdate']) + overrides.map { |o| o['recurrence_id'] || o['start'] }
    event.excluded_dates = excluded.filter_map { |value| date_in_zone(value, first) }.to_set
    event
  end

  # Date of an EXDATE / RECURRENCE-ID value as seen in the series' own time zone
  def date_in_zone(value, reference)
    return Date.parse(value) if value.match?(/\A\d{4}-?\d{2}-?\d{2}\z/)

    Time.parse(value).getlocal(reference.utc_offset).to_date
  rescue ArgumentError
    nil
  end

  def expand(events, from, to)
    days = (from..to).to_h { |date| [date, []] }
    window_start = Time.local(from.year, from.month, from.day)
    window_end = Time.local(to.year, to.month, to.day) + 86_400 - 1

    events.each do |event|
      if event.schedule
        event.schedule.occurrences_between(window_start, window_end, spans: true).each do |occurrence|
          next if event.excluded_dates.include?(occurrence.to_date)

          start = event.all_day ? occurrence.to_date : occurrence.to_time
          finish = start + (event.end - event.start)
          add_occurrence(days, event, start, finish, "#{event.uid}_#{occurrence.strftime('%Y%m%dT%H%M%S')}")
        end
      else
        add_occurrence(days, event, event.start, event.end, event.uid)
      end
    end

    days.each_value { |list| list.sort_by! { |item| [item[:all_day] ? 0 : 1, item[:start], item[:summary]] } }
    days.transform_keys(&:iso8601)
  end

  def add_occurrence(days, event, start, finish, uid)
    item = { uid: uid, summary: event.summary.empty? ? NO_TITLE : event.summary, location: event.location,
             all_day: event.all_day }

    if event.all_day
      item[:start] = start.iso8601
      item[:end] = finish.iso8601
      # All-day end dates are exclusive
      ([start, days.keys.first].max..[finish - 1, days.keys.last].min).each { |date| days[date] << item }
    else
      local_start = start.getlocal
      local_end = finish.getlocal
      item[:start] = local_start.iso8601
      item[:end] = local_end.iso8601
      # Events crossing midnight appear on every day they cover
      last_day = local_end > local_start ? (local_end - 1).to_date : local_start.to_date
      ([local_start.to_date, days.keys.first].max..[last_day, days.keys.last].min).each { |date| days[date] << item }
    end
  end
end

# Fans out data-change notifications to open /updates streams.
class Notifier
  def initialize
    @mutex = Mutex.new
    @subscribers = []
  end

  # Returns nil when too many streams are open
  def subscribe
    queue = Thread::Queue.new
    @mutex.synchronize do
      return if @subscribers.size >= MAX_SSE_CLIENTS

      @subscribers << queue
    end
    queue
  end

  def unsubscribe(queue)
    @mutex.synchronize { @subscribers.delete(queue) }
  end

  def broadcast(message)
    @mutex.synchronize { @subscribers.each { |queue| queue << message } }
  end

  def watch(path)
    Thread.new do
      last_mtime = File.exist?(path) ? File.mtime(path) : nil
      loop do
        sleep WATCH_INTERVAL_SECONDS
        mtime = File.exist?(path) ? File.mtime(path) : nil
        next if mtime.nil? || mtime == last_mtime

        last_mtime = mtime
        LOGGER.info('Calendar data changed, notifying clients')
        broadcast(mtime.to_f.to_s)
      rescue StandardError => e
        LOGGER.error("Watcher error: #{e.message}")
      end
    end
  end
end

STORE = EventStore.new(EVENTS_PATH)
NOTIFIER = Notifier.new
NOTIFIER.watch(EVENTS_PATH)

helpers do
  def asset_path(name)
    "/#{name}?v=#{File.mtime(File.join(settings.public_folder, name)).to_i}"
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def fetcher_checked_at
    Time.iso8601(JSON.parse(File.read(STATUS_PATH))['checked_at'])
  rescue SystemCallError, JSON::ParserError, ArgumentError, TypeError
    nil
  end

  def data_status
    checked_at = fetcher_checked_at
    {
      checked_at: checked_at&.iso8601,
      stale: checked_at.nil? || Time.now - checked_at > STALE_AFTER_SECONDS
    }
  end
end

get '/' do
  cache_control :no_cache
  erb :calendar
end

get '/events' do
  content_type :json
  cache_control :no_store

  from = parse_date(params[:start_date])
  to = parse_date(params[:end_date])
  unless from && to && from <= to && (to - from) < MAX_RANGE_DAYS
    halt 400, { error: "Укажите start_date и end_date (YYYY-MM-DD), не более #{MAX_RANGE_DAYS} дней" }.to_json
  end

  result = STORE.events_between(from, to)
  halt 503, { error: 'Нет данных календаря. Проверьте службу загрузки.' }.to_json unless result

  { events: result[:days], updated_at: STORE.snapshot&.updated_at, **data_status }.to_json
end

get '/updates' do
  content_type 'text/event-stream'
  cache_control :no_store
  headers 'X-Accel-Buffering' => 'no'

  stream do |out|
    queue = NOTIFIER.subscribe
    # Too many open streams: ask the browser to retry much later
    next out << "retry: 60000\n\n" unless queue

    begin
      out << "retry: 5000\n\n"
      loop do
        version = queue.pop(timeout: SSE_HEARTBEAT_SECONDS)
        out << (version ? "event: changed\ndata: #{version}\n\n" : "event: ping\ndata: 1\n\n")
      end
    rescue StandardError
      # Client disconnected
    ensure
      NOTIFIER.unsubscribe(queue)
    end
  end
end

get '/health' do
  content_type :json
  cache_control :no_store
  snapshot = STORE.snapshot
  freshness = data_status
  status(snapshot && !freshness[:stale] ? 200 : 503)
  { status: snapshot ? 'ok' : 'no_data', events: snapshot&.events&.size, updated_at: snapshot&.updated_at,
    **freshness }.to_json
end
