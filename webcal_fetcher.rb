#!/usr/bin/env ruby
require 'net/http'
require 'uri'
require 'logger'
require 'fileutils'
require 'icalendar'
require 'json'
require 'date'
require 'time'

# Set up logging
logger = Logger.new(STDOUT)
logger.level = Logger::INFO
logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] [FETCHER] #{severity}: #{msg}\n"
end

WEBCAL_FILE_PATH = '/app/webcal.ics'
WEBCAL_JSON_PATH = '/app/webcal_events.json'
FETCH_INTERVAL_SECONDS = 60 # 1 minute

# Russian translations for consistent error messages
RUSSIAN_TRANSLATIONS = {
  'All Day' => 'Весь день',
  'No Title' => 'Без названия'
}.freeze

def t(text)
  RUSSIAN_TRANSLATIONS[text] || text
end

def fetch_webcal_data(url, logger)
  begin
    # Convert webcal:// to https://
    if url.start_with?('webcal://')
      url = url.sub('webcal://', 'https://')
    end

    logger.info("Fetching webcal data from #{url}")
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.read_timeout = 30
    http.open_timeout = 10

    request = Net::HTTP::Get.new(uri)
    response = http.request(request)

    if response.is_a?(Net::HTTPSuccess)
      logger.info("Successfully fetched webcal data (#{response.body.length} bytes)")
      return response.body
    else
      logger.error("HTTP error fetching webcal data: #{response.code} - #{response.message}")
      return nil
    end
  rescue => e
    logger.error("Error fetching webcal data: #{e.message}")
    return nil
  end
end

def parse_calendar_events(ical_content, logger)
  begin
    calendars = Icalendar::Calendar.parse(ical_content)
    events = []

    calendars.each do |calendar|
      calendar.events.each do |component|
        next unless component.dtstart

        event = {}

        event['created'] = component.created.to_s
        event['last_modified'] = component.last_modified&.to_s

        event['summary'] = (component.summary.to_s || t('No Title')).dup.force_encoding('UTF-8')
        event['description'] = (component.description.to_s || '').dup.force_encoding('UTF-8')
        event['location'] = (component.location.to_s || '').dup.force_encoding('UTF-8')

        event['start'] = component.dtstart
        event['all_day'] = component.dtstart.is_a?(Icalendar::Values::Date)

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

        event['start'] = event['start'].iso8601
        event['end'] = event['end'].iso8601

        # Extract UID for uniqueness
        event['uid'] = (component.uid.to_s || '').dup.force_encoding('UTF-8')

        # Extract RRULE for recurring events
        if component.rrule && !component.rrule.empty?
          rrule_object = component.rrule.first

          rrule_parts = []
          rrule_parts << "FREQ=#{rrule_object.frequency}" if rrule_object.frequency
          rrule_parts << "UNTIL=#{rrule_object.until}" if rrule_object.until
          rrule_parts << "COUNT=#{rrule_object.count}" if rrule_object.count
          rrule_parts << "INTERVAL=#{rrule_object.interval}" if rrule_object.interval && rrule_object.interval != 1
          rrule_parts << "BYDAY=#{Array(rrule_object.by_day).join(',')}" if rrule_object.by_day && !rrule_object.by_day.empty?
          rrule_parts << "BYMONTHDAY=#{Array(rrule_object.by_month_day).join(',')}" if rrule_object.by_month_day && !rrule_object.by_month_day.empty?
          rrule_parts << "BYMONTH=#{Array(rrule_object.by_month).join(',')}" if rrule_object.by_month && !rrule_object.by_month.empty?
          rrule_parts << "WKST=#{rrule_object.week_start}" if rrule_object.week_start

          event['rrule'] = rrule_parts.join(';') unless rrule_parts.empty?
        end

        if component.exdate && !component.exdate.empty?
          event['exdate'] = []
          Array(component.exdate).each do |exdate_value|
            if exdate_value.is_a?(Array)
              exdate_value.each do |date|
                event['exdate'] << date.to_s
              end
            else
              event['exdate'] << exdate_value.to_s
            end
          end
        end

        events << event
      end
    end

    logger.info("Successfully parsed #{events.length} events from calendar")
    return events
  rescue => e
    logger.error("Error parsing calendar events: #{e.message}")
    return []
  end
end

def save_webcal_data(content, file_path, logger)
  begin
    FileUtils.mkdir_p(File.dirname(file_path))

    utf8_content = content.dup.force_encoding('UTF-8')
    utf8_content = utf8_content.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace, replace: '')

    temp_file = "#{file_path}.tmp"
    File.write(temp_file, utf8_content, encoding: 'UTF-8')
    File.rename(temp_file, file_path)

    logger.info("Successfully saved webcal data to #{file_path}")
    return true
  rescue => e
    logger.error("Error saving webcal data: #{e.message}")
    return false
  end
end

def save_parsed_events(events, file_path, logger)
  begin
    FileUtils.mkdir_p(File.dirname(file_path))

    temp_file = "#{file_path}.tmp"
    File.write(temp_file, JSON.pretty_generate({ events: events, updated_at: Time.now.iso8601 }), encoding: 'UTF-8')
    File.rename(temp_file, file_path)

    logger.info("Successfully saved #{events.length} parsed events to #{file_path}")
    return true
  rescue => e
    logger.error("Error saving parsed events: #{e.message}")
    return false
  end
end

# Check for required environment variable
webcal_url = ENV['WEBCAL_URL']
if webcal_url.nil? || webcal_url.empty?
  logger.error("WEBCAL_URL environment variable not configured")
  exit 1
end

logger.info("Starting webcal fetcher service")
logger.info("WEBCAL_URL: #{webcal_url}")
logger.info("File path: #{WEBCAL_FILE_PATH}")
logger.info("Fetch interval: #{FETCH_INTERVAL_SECONDS} seconds")

logger.info("Starting periodic fetch loop...")
loop do
  content = fetch_webcal_data(webcal_url, logger)
  if content
    save_webcal_data(content, WEBCAL_FILE_PATH, logger)
    events = parse_calendar_events(content, logger)
    save_parsed_events(events, WEBCAL_JSON_PATH, logger)
  else
    logger.warn("Fetch failed, will retry in #{FETCH_INTERVAL_SECONDS} seconds")
  end

  sleep FETCH_INTERVAL_SECONDS
end
