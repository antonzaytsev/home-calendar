require 'sinatra'
require 'net/http'
require 'uri'
require 'icalendar'
require 'json'
require 'date'
require 'time'
require 'logger'

# Set default encoding to UTF-8
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

# Set up logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO

# Configure Sinatra
set :port, ENV['APP_PORT']
set :bind, '0.0.0.0'

def fetch_webcal_data(webcal_url)
  """Fetch calendar data from webcal URL"""
  begin
    # Convert webcal:// to https://
    if webcal_url.start_with?('webcal://')
      webcal_url = webcal_url.sub('webcal://', 'https://')
    end

    uri = URI(webcal_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 10

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      return response.body
    else
      logger.error("HTTP error fetching webcal data: #{response.code}")
      return nil
    end
  rescue => e
    logger.error("Error fetching webcal data: #{e}")
    return nil
  end
end

def parse_calendar_events(ical_content)
  """Parse iCal content and extract events"""
  begin
    calendars = Icalendar::Calendar.parse(ical_content)
    events = []

    calendars.each do |calendar|
      calendar.events.each do |component|
        event = {}

        # Extract basic event information
        event['summary'] = (component.summary.to_s || 'No Title').dup.force_encoding('UTF-8')
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
  """Get 7 days centered around target date (target date in middle)"""
  if target_date.nil?
    target_date = Date.today
  elsif target_date.is_a?(String)
    target_date = Date.parse(target_date)
  elsif target_date.is_a?(Time) || target_date.is_a?(DateTime)
    target_date = target_date.to_date
  end

  # Put target date in the middle (position 3 of 7)
  start_day = target_date - 3
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
  return 'All Day' if event['all_day']

  begin
    if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
      start_time = event['start'].strftime('%H:%M')
      end_time = event['end'].strftime('%H:%M')
      return "#{start_time} - #{end_time}"
    else
      return 'All Day'
    end
  rescue
    return 'All Day'
  end
end

get '/' do
  """Main calendar view"""
  webcal_url = ENV['WEBCAL_URL']
  @error = nil
  @week_events = {}
  @week_dates = get_week_dates

  if webcal_url
    # Fetch and parse calendar data
    ical_content = fetch_webcal_data(webcal_url)
    if ical_content
      all_events = parse_calendar_events(ical_content)
      @week_events = filter_events_for_week(all_events, @week_dates)
    else
      @error = "Failed to fetch calendar data. Please check your webcal URL."
    end
  else
    @error = "WEBCAL_URL environment variable not configured."
  end

  @today = Date.today
  erb :calendar
end

get '/api/calendar/events' do
  """API endpoint to get calendar events"""
  content_type :json

  webcal_url = ENV['WEBCAL_URL']

  if webcal_url.nil? || webcal_url.empty?
    status 400
    return { error: 'WEBCAL_URL environment variable not configured' }.to_json
  end

  # Fetch and parse calendar data
  ical_content = fetch_webcal_data(webcal_url)
  if ical_content.nil?
    status 500
    return { error: 'Failed to fetch calendar data' }.to_json
  end

  all_events = parse_calendar_events(ical_content)

  # Convert events to JSON-serializable format
  json_events = []
  all_events.each do |event|
    json_event = {
      uid: event['uid'],
      summary: event['summary'],
      description: event['description'],
      location: event['location'],
      all_day: event['all_day']
    }

    # Convert dates to ISO format
    if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
      json_event[:start] = event['start'].iso8601
      json_event[:end] = event['end'].iso8601
    else
      json_event[:start] = event['start'].iso8601
      json_event[:end] = event['end'].iso8601
    end

    json_events << json_event
  end

  { events: json_events }.to_json
end

get '/health' do
  """Health check endpoint"""
  content_type :json
  { status: 'healthy', timestamp: Time.now.iso8601 }.to_json
end

# Helper methods for ERB templates
helpers do
  def format_event_time(event)
    return 'All Day' if event['all_day']

    begin
      if event['start'].is_a?(Icalendar::Values::DateTime) || event['start'].is_a?(Time)
        start_time = event['start'].strftime('%H:%M')
        end_time = event['end'].strftime('%H:%M')
        return "#{start_time} - #{end_time}"
      else
        return 'All Day'
      end
    rescue
      return 'All Day'
    end
  end
end
