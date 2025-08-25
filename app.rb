require 'sinatra'
require 'icalendar'
require 'json'
require 'date'
require 'time'
require 'logger'

set :port, ENV['APP_PORT']
set :bind, '0.0.0.0'

PAGE_REFRESH_MINUTES = 1
WEBCAL_FILE_PATH = '/app/webcal.ics'
WEBCAL_JSON_PATH = '/app/webcal_events.json'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

Date::MONTHNAMES = [nil, 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь']
Date::DAYNAMES = ['воскресенье', 'понедельник', 'вторник', 'среда', 'четверг', 'пятница', 'суббота']
Date::ABBR_DAYNAMES = ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб']
Date::ABBR_MONTHNAMES = [nil, 'янв', 'фев', 'мар', 'апр', 'май', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек']

RUSSIAN_TRANSLATIONS = {
  'All Day' => 'Весь день',
  'No Title' => 'Без названия',
  'Failed to read calendar data from file. Check if fetcher service is running.' => 'Не удалось прочитать данные календаря из файла. Проверьте работу службы загрузки.',
  'Failed to read calendar data from file' => 'Не удалось прочитать данные календаря из файла',
  'healthy' => 'исправно'
}.freeze

def t(text)
  RUSSIAN_TRANSLATIONS[text] || text
end

# Set up logging

def logger
  return @logger if @logger

  @logger = Logger.new(STDOUT)
  @logger.level = Logger::INFO
  @logger
end

def read_parsed_events_from_json
  begin
    if File.exist?(WEBCAL_JSON_PATH)
      json_content = File.read(WEBCAL_JSON_PATH, encoding: 'UTF-8')
      parsed_data = JSON.parse(json_content)
      events = parsed_data['events'] || []

      converted_events = []
      events.each do |json_event|
        event = {
          'uid' => json_event['uid'] || '',
          'summary' => json_event['summary'] || t('No Title'),
          'description' => json_event['description'] || '',
          'location' => json_event['location'] || '',
          'all_day' => json_event['all_day'] || false
        }

        begin
          if json_event['start']
            if event['all_day']
              event['start'] = Date.parse(json_event['start'])
              event['end'] = Date.parse(json_event['end'])
            else
              event['start'] = Time.parse(json_event['start'])
              event['end'] = Time.parse(json_event['end'])
            end
          else
            next
          end
        rescue => e
          logger.warn("Error parsing event dates for #{event['summary']}: #{e.message}")
          next
        end

        converted_events << event
      end

      logger.info("Successfully read #{converted_events.length} events from JSON cache")
      return converted_events
    else
      logger.warn("JSON cache file not found at #{WEBCAL_JSON_PATH}, falling back to ical parsing")
      return nil
    end
  rescue => e
    logger.error("Error reading JSON cache: #{e.message}, falling back to ical parsing")
    return nil
  end
end

def read_webcal_data_from_file_fallback
  begin
    if File.exist?(WEBCAL_FILE_PATH)
      content = File.read(WEBCAL_FILE_PATH, encoding: 'UTF-8')
      logger.info("Fallback: reading and parsing ical data from filesystem (#{content.length} bytes)")
      return parse_calendar_events(content)
    else
      logger.error("Webcal file not found at #{WEBCAL_FILE_PATH}")
      return []
    end
  rescue => e
    logger.error("Error reading webcal data from file: #{e.message}")
    return []
  end
end

def parse_calendar_events(ical_content)
  begin
    calendars = Icalendar::Calendar.parse(ical_content)
    events = []

    calendars.each do |calendar|
      calendar.events.each do |component|
        event = {}

        # Extract basic event information
        event['summary'] = (component.summary.to_s || t('No Title')).dup.force_encoding('UTF-8')
        event['description'] = (component.description.to_s || '').dup.force_encoding('UTF-8')
        event['location'] = (component.location.to_s || '').dup.force_encoding('UTF-8')

        # Handle start time
        if component.dtstart
          event['start'] = component.dtstart
          event['all_day'] = component.dtstart.is_a?(Icalendar::Values::Date)
        else
          next # Skip events without start time
        end

        # Handle end time
        if component.dtend
          event['end'] = component.dtend
        else
          # If no end time, assume 1 hour duration for timed events
          if event['all_day']
            event['end'] = event['start']
          else
            event['end'] = event['start'] + (60 * 60) # Add 1 hour in seconds
          end
        end

        # Extract UID for uniqueness
        event['uid'] = (component.uid.to_s || '').dup.force_encoding('UTF-8')

        events << event
      end
    end

    return events
  rescue => e
    logger.error("Error parsing calendar events: #{e}")
    return []
  end
end

def get_week_dates(target_date = nil)
  if target_date.nil?
    target_date = Date.today
  elsif target_date.is_a?(String)
    target_date = Date.parse(target_date)
  elsif target_date.is_a?(Time) || target_date.is_a?(DateTime)
    target_date = target_date.to_date
  end

  start_day = target_date - 1
  (0..6).map { |i| start_day + i }
end

def filter_events_for_week(events, week_dates)
  """Filter events to show only those in the given week"""
  week_start = week_dates.first
  week_end = week_dates.last

  week_events = {}
  week_dates.each { |date| week_events[date] = [] }

  events.each do |event|
    begin
      # Convert event dates to date objects for comparison
      if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
        event_start_date = event['start'].to_date
      else
        event_start_date = event['start']
      end

      if event['end'].is_a?(Icalendar::Values::DateTime) || event['end'].is_a?(Time)
        event_end_date = event['end'].to_date
      else
        event_end_date = event['end']
      end

      # Check if event overlaps with any day in the week
      week_dates.each do |date|
        if event_start_date <= date && date <= event_end_date
          week_events[date] << event
          break # Event added, no need to check other days
        end
      end

    rescue => e
      logger.warn("Error processing event #{event['summary'] || 'Unknown'}: #{e}")
      next
    end
  end

  week_events
end

def format_event_time(event)
  """Format event time for display"""
  return t('All Day') if event['all_day']

  begin
    if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
      start_time = event['start'].strftime('%H:%M')
      end_time = event['end'].strftime('%H:%M')
      return "#{start_time} - #{end_time}"
    else
      return t('All Day')
    end
  rescue
    return t('All Day')
  end
end

get '/' do
  target_date = nil
  if params[:date]
    begin
      target_date = Date.parse(params[:date])
    rescue => e
      target_date = nil
    end
  end

  @error = nil
  @week_events = {}
  @week_dates = get_week_dates(target_date)

  all_events = read_parsed_events_from_json
  if all_events.nil?
    all_events = read_webcal_data_from_file_fallback
  end

  if all_events && !all_events.empty?
    @week_events = filter_events_for_week(all_events, @week_dates)
  else
    @error = t("Failed to read calendar data from file. Check if fetcher service is running.")
  end

  current_reference_date = @week_dates[1]
  @prev_week_date = (current_reference_date - 7).strftime('%Y-%m-%d')
  @next_week_date = (current_reference_date + 7).strftime('%Y-%m-%d')

  @today = Date.today
  @now = Time.now.getlocal("+03:00")
  @current_time_minutes = @now.hour * 60 + @now.min
  erb :calendar
end


get '/health' do
  content_type :json
  { status: t('healthy'), timestamp: Time.now.getlocal("+03:00").iso8601 }.to_json
end

# Helper methods for ERB templates
helpers do
  def format_event_time(event)
    return t('All Day') if event['all_day']

    begin
      if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
        start_time = event['start'].strftime('%H:%M')
        end_time = event['end'].strftime('%H:%M')
        return "#{start_time} - #{end_time}"
      else
        return t('All Day')
      end
    rescue
      return t('All Day')
    end
  end

  def event_top_position(event)
    return 0 if event['all_day']

    begin
      if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
        start_time = event['start']
        minutes_from_midnight = start_time.hour * 60 + start_time.min
        return (minutes_from_midnight * 60) / 60.0  # 60px per hour
      end
    rescue
      return 0
    end
    0
  end

  def event_height(event)
    return 20 if event['all_day']

    begin
      if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time) &&
         event['end'].is_a?(Icalendar::Values::DateTime) || event['end'].is_a?(Time)
        start_minutes = event['start'].hour * 60 + event['start'].min
        end_minutes = event['end'].hour * 60 + event['end'].min
        duration_minutes = end_minutes - start_minutes
        return [(duration_minutes * 60) / 60.0, 20].max  # minimum 20px height
      end
    rescue
      return 20
    end
    20
  end

  def format_hour(hour)
    return "#{hour}:00" # Use 24-hour format for Russian locale
  end

  def event_is_past?(event, current_date, current_time)
    """Check if an event is in the past"""
    begin
      if event['all_day']
        # For all-day events, check if the event date is before today
        if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
          event_date = event['start'].to_date
        else
          event_date = event['start']
        end
        return event_date < current_date
      else
        # For timed events, check if the event end time is before current time
        if event['end'].is_a?(Icalendar::Values::DateTime) || event['end'].is_a?(Time)
          event_end_time = event['end']
          # Compare with current time
          return event_end_time < current_time
        end
      end
    rescue => e
      logger.warn("Error checking if event is past: #{e}")
      return false
    end
    false
  end
end
