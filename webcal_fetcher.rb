#!/usr/bin/env ruby
require 'bundler/setup'
require 'digest'
require 'icalendar'
require 'json'
require 'logger'
require 'net/http'
require 'time'

EVENTS_PATH = File.join(__dir__, 'webcal_events.json')
STATUS_PATH = File.join(__dir__, 'webcal_status.json')
FETCH_INTERVAL_SECONDS = Integer(ENV.fetch('FETCH_INTERVAL_SECONDS', 60))
MAX_REDIRECTS = 5

$stdout.sync = true
LOGGER = Logger.new($stdout, level: Logger::INFO)
LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] [FETCHER] #{severity}: #{msg}\n"
end

# Returns the response, or nil when the calendar is unchanged since the last fetch
def fetch_calendar(url, etag:, last_modified:, redirects_left: MAX_REDIRECTS)
  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  request['If-None-Match'] = etag if etag
  request['If-Modified-Since'] = last_modified if last_modified

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                                 open_timeout: 10, read_timeout: 30) do |http|
    http.request(request)
  end

  case response
  when Net::HTTPNotModified
    nil
  when Net::HTTPSuccess
    response
  when Net::HTTPRedirection
    raise 'Too many redirects' if redirects_left.zero?

    fetch_calendar(URI.join(url, response['location']).to_s, etag: etag, last_modified: last_modified,
                                                              redirects_left: redirects_left - 1)
  else
    raise "HTTP #{response.code} #{response.message}"
  end
end

def text(value)
  value.to_s.dup.force_encoding('UTF-8').scrub('')
end

def serialize_rrule(rule)
  parts = []
  parts << "FREQ=#{rule.frequency}" if rule.frequency
  parts << "UNTIL=#{rule.until}" if rule.until
  parts << "COUNT=#{rule.count}" if rule.count
  parts << "INTERVAL=#{rule.interval}" if rule.interval && rule.interval.to_i != 1
  { 'BYDAY' => rule.by_day, 'BYMONTHDAY' => rule.by_month_day, 'BYMONTH' => rule.by_month,
    'BYSETPOS' => rule.by_set_position }.each do |key, values|
    parts << "#{key}=#{Array(values).join(',')}" unless Array(values).empty?
  end
  parts << "WKST=#{rule.week_start}" if rule.week_start
  parts.join(';')
end

def duration_seconds(duration)
  return unless duration

  seconds = ((duration.weeks * 7 + duration.days) * 86_400) + (duration.hours * 3600) + (duration.minutes * 60) +
            duration.seconds
  duration.past ? -seconds : seconds
end

# DTEND, else DTSTART + DURATION, else one day (all-day) or one hour
def event_end(component, start, all_day)
  return component.dtend if component.dtend

  seconds = duration_seconds(component.duration)
  return start + [seconds.to_i / 86_400, 1].max if all_day

  start.to_time + (seconds || 3600)
end

def serialize_event(component)
  return unless component.dtstart

  start = component.dtstart
  all_day = start.is_a?(Icalendar::Values::Date)
  finish = event_end(component, start, all_day)

  event = {
    'uid' => text(component.uid),
    'summary' => text(component.summary),
    'location' => text(component.location),
    'all_day' => all_day,
    'start' => start.iso8601,
    'end' => finish.iso8601
  }

  rule = component.rrule.first
  event['rrule'] = serialize_rrule(rule) if rule
  exdates = component.exdate.flatten.map(&:iso8601)
  event['exdate'] = exdates unless exdates.empty?
  event['recurrence_id'] = component.recurrence_id.iso8601 if component.recurrence_id
  event
end

def parse_events(ics)
  events = Icalendar::Calendar.parse(ics).flat_map(&:events).filter_map do |component|
    serialize_event(component)
  rescue StandardError => e
    LOGGER.warn("Skipping event #{component.uid}: #{e.message}")
    nil
  end
  raise 'Calendar contains no events' if events.empty?

  events
end

def write_json(path, data)
  temp_path = "#{path}.tmp"
  File.write(temp_path, JSON.generate(data))
  File.rename(temp_path, path)
end

# Allow loading the helpers above without starting the fetch loop
return unless $PROGRAM_NAME == __FILE__

webcal_url = ENV['WEBCAL_URL'].to_s.sub(%r{\Awebcal://}, 'https://')
if webcal_url.empty?
  LOGGER.error('WEBCAL_URL environment variable is not configured')
  exit 1
end

LOGGER.info("Fetching #{URI(webcal_url).host} every #{FETCH_INTERVAL_SECONDS} seconds")
etag = last_modified = digest = nil

loop do
  begin
    response = fetch_calendar(webcal_url, etag: etag, last_modified: last_modified)
    if response
      body = response.body
      body_digest = Digest::SHA256.hexdigest(body)
      if body_digest != digest
        events = parse_events(body)
        write_json(EVENTS_PATH, { events: events, updated_at: Time.now.iso8601 })
        LOGGER.info("Saved #{events.size} events (#{body.bytesize} bytes)")
        digest = body_digest
      end
      etag = response['etag']
      last_modified = response['last-modified']
    end
    write_json(STATUS_PATH, { checked_at: Time.now.iso8601 })
  rescue StandardError => e
    # Keep the last good data; the app reports it as stale if this persists
    LOGGER.error("Fetch failed: #{e.class}: #{e.message}")
  end

  sleep FETCH_INTERVAL_SECONDS
end
