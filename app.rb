require 'bundler/setup'
Bundler.require

require 'date'
require 'time'
require 'logger'

set :port, ENV['APP_PORT']
set :bind, '0.0.0.0'
set :public_folder, 'public'

PAGE_REFRESH_MINUTES = 1
WEBCAL_FILE_PATH = '/app/webcal.ics'
WEBCAL_JSON_PATH = '/app/webcal_events.json'

DAYS_IN_PAST = 1
DAYS_IN_FUTURE = 2
TOTAL_DAYS = DAYS_IN_PAST + 1 + DAYS_IN_FUTURE

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

def logger
  return @logger if @logger

  @logger = Logger.new(STDOUT)
  @logger.level = Logger::INFO
  @logger
end

def read_parsed_events_from_json
  unless File.exist?(WEBCAL_JSON_PATH)
    logger.warn("JSON cache file not found at #{WEBCAL_JSON_PATH}, falling back to ical parsing")
    return
  end

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

    if json_event['rrule']
      event['rrule'] = json_event['rrule']
    end

    if json_event['exdate']
      event['exdate'] = json_event['exdate']
    end

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
  converted_events

rescue => e
  logger.error("Error reading JSON cache: #{e.message}, falling back to ical parsing")
  return
end

def filter_events_for_week(events, week_dates)
  week_events = {}
  week_dates.each { |date| week_events[date] = [] }

  events.each do |event|
    begin
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

def parse_rrule(rrule_string)
  rrule = {}
  return rrule if rrule_string.nil? || rrule_string.empty?

  parts = rrule_string.split(';')
  parts.each do |part|
    key, value = part.split('=', 2)
    next unless key && value
    rrule[key.upcase] = value
  end
  rrule
end

def parse_byday(byday_string)
  """Parse BYDAY string and return array of Ruby wday integers (0=Sunday, 1=Monday, etc.)"""
  return [] if byday_string.nil? || byday_string.empty?
  
  day_map = {
    'SU' => 0, 'MO' => 1, 'TU' => 2, 'WE' => 3, 
    'TH' => 4, 'FR' => 5, 'SA' => 6
  }
  
  days = byday_string.split(',').map(&:strip).map(&:upcase)
  days.map { |day| day_map[day] }.compact
end

def expand_recurring_event(event, start_date, end_date)
  return [event] unless event['rrule']

  rrule = parse_rrule(event['rrule'])
  return [event] if rrule.empty?

  occurrences = []
  exdates = []

  # Parse exdate list if present
  if event['exdate']
    exdates = event['exdate'].map { |date_str|
      begin
        if event['all_day']
          Date.parse(date_str.split('T')[0])
        else
          Time.parse(date_str)
        end
      rescue
        nil
      end
    }.compact
  end

  # Get the original event start time
  original_start = event['start']
  original_end = event['end']

  # Calculate duration
  if event['all_day']
    duration_days = (original_end - original_start).to_i
  else
    duration_seconds = original_end - original_start
  end

  freq = rrule['FREQ']
  until_date = nil
  count = nil
  byday_wdays = []

  if rrule['UNTIL']
    begin
      until_date = Time.parse(rrule['UNTIL'])
    rescue
      until_date = nil
    end
  end

  if rrule['COUNT']
    count = rrule['COUNT'].to_i
  end

  # Parse BYDAY for weekly frequency
  if freq == 'WEEKLY' && rrule['BYDAY']
    byday_wdays = parse_byday(rrule['BYDAY'])
  end

  current_date = original_start
  occurrence_count = 0

  # For weekly BYDAY events, adjust starting date to first valid occurrence
  if freq == 'WEEKLY' && !byday_wdays.empty?
    original_wday = event['all_day'] ? original_start.wday : original_start.to_date.wday
    
    # If original start date is not on a valid weekday, find the next valid one
    unless byday_wdays.include?(original_wday)
      search_date = original_start
      
      # Look ahead up to 7 days to find first valid weekday
      7.times do
        if event['all_day']
          search_date += 1
          search_wday = search_date.wday
        else
          search_date += 24 * 60 * 60
          search_wday = search_date.to_date.wday
        end
        
        if byday_wdays.include?(search_wday)
          current_date = search_date
          break
        end
      end
    end
  end

  # Limit iterations to prevent infinite loops
  max_iterations = 1000
  iteration_count = 0

  while iteration_count < max_iterations
    iteration_count += 1

    # Break if we've reached the count limit
    break if count && occurrence_count >= count

    # Break if we've passed the until date
    if until_date
      check_date = event['all_day'] ? current_date : current_date
      break if check_date > until_date
    end

    # Break if we're past our search range
    search_date = event['all_day'] ? current_date : current_date.to_date
    break if search_date > end_date

    # For weekly BYDAY events, check if current day is valid
    if freq == 'WEEKLY' && !byday_wdays.empty?
      current_wday = event['all_day'] ? current_date.wday : current_date.to_date.wday
      if !byday_wdays.include?(current_wday)
        # Skip to next day and continue
        if event['all_day']
          current_date += 1
        else
          current_date += 24 * 60 * 60
        end
        next
      end
    end

    # Check if this occurrence is within our range and not excluded
    if search_date >= start_date && search_date <= end_date
      # Check if this date is excluded
      excluded = false
      exdates.each do |exdate|
        if event['all_day']
          excluded = (current_date == exdate)
        else
          # For timed events, check if the start date matches
          excluded = (current_date.to_date == exdate.to_date)
        end
        break if excluded
      end

      unless excluded
        # Create occurrence
        occurrence = event.dup
        occurrence['start'] = current_date

        if event['all_day']
          occurrence['end'] = current_date + duration_days
        else
          occurrence['end'] = current_date + duration_seconds
        end

        # Generate unique UID for this occurrence
        if event['all_day']
          occurrence['uid'] = "#{event['uid']}_#{current_date.strftime('%Y%m%d')}"
        else
          occurrence['uid'] = "#{event['uid']}_#{current_date.strftime('%Y%m%dT%H%M%S')}"
        end

        # Remove rrule from occurrence (it's not a recurring event anymore)
        occurrence.delete('rrule')

        occurrences << occurrence
        occurrence_count += 1
      end
    end

    # Calculate next occurrence based on frequency
    case freq
    when 'DAILY'
      if event['all_day']
        current_date += 1
      else
        current_date += 24 * 60 * 60 # Add 1 day in seconds
      end
    when 'WEEKLY'
      if !byday_wdays.empty?
        # For BYDAY weekly events, just move to next day - the loop logic will handle finding valid weekdays
        if event['all_day']
          current_date += 1
        else
          current_date += 24 * 60 * 60 # Add 1 day in seconds
        end
      else
        # Standard weekly recurrence (every 7 days)
        if event['all_day']
          current_date += 7
        else
          current_date += 7 * 24 * 60 * 60 # Add 7 days in seconds
        end
      end
    when 'MONTHLY'
      if event['all_day']
        current_date = Date.new(current_date.year, current_date.month, current_date.day) >> 1
      else
        # Add 1 month, keeping the same time
        date_part = current_date.to_date >> 1
        current_date = Time.new(date_part.year, date_part.month, date_part.day,
                               current_date.hour, current_date.min, current_date.sec,
                               current_date.zone)
      end
    when 'YEARLY'
      if event['all_day']
        current_date = Date.new(current_date.year + 1, current_date.month, current_date.day)
      else
        # Add 1 year, keeping the same time
        current_date = Time.new(current_date.year + 1, current_date.month, current_date.day,
                               current_date.hour, current_date.min, current_date.sec,
                               current_date.zone)
      end
    else
      # Unknown frequency, break to prevent infinite loop
      break
    end

    # Safety check: if we're way past our search range, break
    search_date = event['all_day'] ? current_date : current_date.to_date
    break if search_date > end_date + 365 # Stop if more than a year past range
  end

  occurrences
end

def extract_base_uid(uid)
  # Remove timestamp suffix from generated UIDs (e.g., "original_uid_20240101" -> "original_uid")
  uid.gsub(/_\d{8}(T\d{6})?$/, '')
end

def deduplicate_events_by_uid(events)
  # Group events by base UID
  grouped_by_uid = events.group_by { |event| extract_base_uid(event['uid']) }
  
  # For each group, keep only the latest created event (last in array = most recently processed/created)
  deduplicated = []
  grouped_by_uid.each do |base_uid, uid_events|
    if uid_events.length > 1
      # Keep the last event in the array (latest created/processed)
      latest_event = uid_events.last
      deduplicated << latest_event
    else
      deduplicated << uid_events.first
    end
  end
  
  deduplicated
end

def filter_events_for_week_with_recurring(events, week_dates)
  week_events = {}
  week_dates.each { |date| week_events[date] = [] }

  start_date = week_dates.first
  end_date = week_dates.last

  events.each do |event|
    begin
      if event['rrule']
        # Expand recurring event
        expanded_events = expand_recurring_event(event, start_date, end_date)
        expanded_events.each do |expanded_event|
          # Add expanded occurrence to appropriate date
          if expanded_event['start'].is_a?(Icalendar::Values::DateTime) || expanded_event['start'].is_a?(Time)
            event_start_date = expanded_event['start'].to_date
          else
            event_start_date = expanded_event['start']
          end

          if expanded_event['end'].is_a?(Icalendar::Values::DateTime) || expanded_event['end'].is_a?(Time)
            event_end_date = expanded_event['end'].to_date
          else
            event_end_date = expanded_event['end']
          end

          # Check if event overlaps with any day in the week
          week_dates.each do |date|
            if event_start_date <= date && date <= event_end_date
              week_events[date] << expanded_event
              break # Event added, no need to check other days
            end
          end
        end
      else
        # Handle non-recurring events (existing logic)
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
      end
    rescue => e
      logger.warn("Error processing event #{event['summary'] || 'Unknown'}: #{e}")
      next
    end
  end

  # Deduplicate events by base UID for each day
  week_events.each do |date, events|
    next if events.empty?
    
    # Remove duplicates with same base UID, keeping the latest
    week_events[date] = deduplicate_events_by_uid(events)
  end

  week_events
end

get '/' do
  erb :calendar
end


get '/events' do
  content_type :json

  # Get date range from parameters
  start_date_param = params[:start_date]
  end_date_param = params[:end_date]

  unless start_date_param && end_date_param
    halt 400, { error: 'start_date and end_date parameters are required' }.to_json
  end

  begin
    start_date = Date.parse(start_date_param)
    end_date = Date.parse(end_date_param)
  rescue => e
    halt 400, { error: 'Invalid date format. Use YYYY-MM-DD' }.to_json
  end

  all_events = read_parsed_events_from_json

  if all_events.nil? || all_events.empty?
    return {
      events: {},
      error: t("Failed to read calendar data from file. Check if fetcher service is running.")
    }.to_json
  end

  week_dates = []
  current_date = start_date
  while current_date <= end_date
    week_dates << current_date
    current_date = current_date + 1
  end

  week_events = filter_events_for_week_with_recurring(all_events, week_dates)

  json_events = {}
  week_events.each do |date, events|
    date_key = date.strftime('%Y-%m-%d')
    json_events[date_key] = events.map do |event|
      event_json = {
        uid: event['uid'],
        summary: event['summary'],
        description: event['description'],
        location: event['location'],
        all_day: event['all_day'],
        start: event['start'].respond_to?(:iso8601) ? event['start'].iso8601 : event['start'].to_s,
        end: event['end'].respond_to?(:iso8601) ? event['end'].iso8601 : event['end'].to_s
      }

      if event['rrule']
        event_json[:rrule] = event['rrule']
      end

      if event['exdate']
        event_json[:exdate] = event['exdate']
      end

      event_json
    end
  end

  {
    events: json_events,
    timestamp: Time.now.getlocal("+03:00").iso8601
  }.to_json
end

get '/health' do
  content_type :json
  { status: t('healthy'), timestamp: Time.now.getlocal("+03:00").iso8601 }.to_json
end

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

  def events_overlap?(event1, event2)
    """Check if two timed events overlap"""
    return false if event1['all_day'] || event2['all_day']

    begin
      start1_minutes = event1['start'].hour * 60 + event1['start'].min
      end1_minutes = event1['end'].hour * 60 + event1['end'].min
      start2_minutes = event2['start'].hour * 60 + event2['start'].min
      end2_minutes = event2['end'].hour * 60 + event2['end'].min

      # Events overlap if start of one is before end of other, and vice versa
      return start1_minutes < end2_minutes && start2_minutes < end1_minutes
    rescue => e
      logger.warn("Error checking event overlap: #{e}")
      return false
    end
  end

  def calculate_event_columns(events)
    """Calculate column positions for overlapping events"""
    return {} if events.empty?

    # Filter out all-day events as they are handled separately
    timed_events = events.reject { |event| event['all_day'] }
    return {} if timed_events.empty?

    # Sort events by start time
    sorted_events = timed_events.sort_by do |event|
      begin
        event['start'].hour * 60 + event['start'].min
      rescue
        0
      end
    end

    event_columns = {}
    columns = [] # Array of arrays, each containing events in that column

    sorted_events.each do |event|
      # Find the first column where this event doesn't overlap with any existing event
      column_index = 0

      columns.each_with_index do |column_events, index|
        overlaps = false
        column_events.each do |existing_event|
          if events_overlap?(event, existing_event)
            overlaps = true
            break
          end
        end

        if !overlaps
          column_index = index
          break
        end
        column_index = index + 1
      end

      # Ensure we have enough columns
      while columns.length <= column_index
        columns << []
      end

      # Add event to the column
      columns[column_index] << event

      # Store the column info for this event
      event_columns[event['uid']] = {
        column: column_index,
        total_columns: columns.length,
        overlapping_events: []
      }
    end

    # Update total_columns for all events and find overlapping groups
    event_columns.each do |uid, info|
      event = sorted_events.find { |e| e['uid'] == uid }
      overlapping_events = []

      sorted_events.each do |other_event|
        if event != other_event && events_overlap?(event, other_event)
          overlapping_events << other_event
        end
      end

      if !overlapping_events.empty?
        # Calculate total columns needed for this overlapping group
        group_columns = overlapping_events.map { |e| event_columns[e['uid']]&.dig(:column) }.compact + [info[:column]]
        max_column = group_columns.max
        total_columns_needed = max_column + 1

        info[:total_columns] = total_columns_needed
        info[:overlapping_events] = overlapping_events

        # Update all events in the overlapping group
        overlapping_events.each do |overlapping_event|
          if event_columns[overlapping_event['uid']]
            event_columns[overlapping_event['uid']][:total_columns] = total_columns_needed
          end
        end
      end
    end

    event_columns
  end

  def event_left_position(event, event_columns)
    """Calculate left position percentage for an event based on its column"""
    column_info = event_columns[event['uid']]
    return 2 unless column_info # default position if no overlap info

    column = column_info[:column]
    total_columns = column_info[:total_columns]

    # Calculate position as percentage, leaving small margins
    available_width = 96.0 # Use 96% to leave 2% margins on each side
    column_width_percent = available_width / total_columns
    left_percentage = 2.0 + (column * column_width_percent) # Start at 2% margin

    left_percentage.round(2)
  end

  def event_width(event, event_columns)
    """Calculate width percentage for an event based on its column"""
    column_info = event_columns[event['uid']]
    return nil unless column_info # default width if no overlap info

    total_columns = column_info[:total_columns]
    return nil if total_columns <= 1

    # Calculate width as percentage with small gap between events
    available_width = 96.0 # Use 96% to leave margins
    column_width_percent = available_width / total_columns
    gap_percent = 0.5 # small gap between events
    width_percent = column_width_percent - gap_percent

    width_percent.round(2)
  end
end
