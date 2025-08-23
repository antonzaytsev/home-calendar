from flask import Flask, render_template, jsonify
import requests
import icalendar
import datetime as dt
from datetime import timedelta
import pytz
from dateutil import parser
import logging
import os

app = Flask(__name__)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def fetch_webcal_data(webcal_url):
    """Fetch calendar data from webcal URL"""
    try:
        # Convert webcal:// to https://
        if webcal_url.startswith('webcal://'):
            webcal_url = webcal_url.replace('webcal://', 'https://')
        
        response = requests.get(webcal_url, timeout=10)
        response.raise_for_status()
        
        return response.content
    except requests.RequestException as e:
        logger.error(f"Error fetching webcal data: {e}")
        return None

def parse_calendar_events(ical_content):
    """Parse iCal content and extract events"""
    try:
        cal = icalendar.Calendar.from_ical(ical_content)
        events = []
        
        for component in cal.walk():
            if component.name == "VEVENT":
                event = {}
                
                # Extract basic event information
                event['summary'] = str(component.get('summary', 'No Title'))
                event['description'] = str(component.get('description', ''))
                event['location'] = str(component.get('location', ''))
                
                # Handle start time
                dtstart = component.get('dtstart')
                if dtstart:
                    if hasattr(dtstart.dt, 'date'):
                        event['start'] = dtstart.dt
                        event['all_day'] = isinstance(dtstart.dt, dt.date) and not isinstance(dtstart.dt, dt.datetime)
                    else:
                        event['start'] = dtstart.dt
                        event['all_day'] = False
                else:
                    continue  # Skip events without start time
                
                # Handle end time
                dtend = component.get('dtend')
                if dtend:
                    if hasattr(dtend.dt, 'date'):
                        event['end'] = dtend.dt
                    else:
                        event['end'] = dtend.dt
                else:
                    # If no end time, assume 1 hour duration for timed events
                    if not event['all_day']:
                        event['end'] = event['start'] + timedelta(hours=1)
                    else:
                        event['end'] = event['start']
                
                # Extract UID for uniqueness
                event['uid'] = str(component.get('uid', ''))
                
                events.append(event)
        
        return events
    except Exception as e:
        logger.error(f"Error parsing calendar events: {e}")
        return []

def get_week_dates(target_date=None):
    """Get 7 days centered around target date (target date in middle)"""
    if target_date is None:
        target_date = dt.datetime.now().date()
    elif isinstance(target_date, dt.datetime):
        target_date = target_date.date()
    elif isinstance(target_date, str):
        target_date = parser.parse(target_date).date()
    
    # Put target date in the middle (position 3 of 7)
    start_day = target_date - timedelta(days=3)
    return [start_day + timedelta(days=i) for i in range(7)]

def filter_events_for_week(events, week_dates):
    """Filter events to show only those in the given week"""
    week_start = week_dates[0]
    week_end = week_dates[-1]
    
    week_events = {date: [] for date in week_dates}
    
    for event in events:
        try:
            # Convert event dates to date objects for comparison
            if isinstance(event['start'], dt.datetime):
                event_start_date = event['start'].date()
                event_end_date = event['end'].date()
            else:
                event_start_date = event['start']
                event_end_date = event['end']
            
            # Check if event overlaps with any day in the week
            for date in week_dates:
                if event_start_date <= date <= event_end_date:
                    week_events[date].append(event)
                    break  # Event added, no need to check other days
                    
        except Exception as e:
            logger.warning(f"Error processing event {event.get('summary', 'Unknown')}: {e}")
            continue
    
    return week_events

def format_event_time(event):
    """Format event time for display"""
    if event['all_day']:
        return 'All Day'
    
    try:
        if isinstance(event['start'], dt.datetime):
            start_time = event['start'].strftime('%H:%M')
            end_time = event['end'].strftime('%H:%M')
            return f"{start_time} - {end_time}"
        else:
            return 'All Day'
    except:
        return 'All Day'

@app.route('/')
def calendar_view():
    """Main calendar view"""
    webcal_url = os.getenv('WEBCAL_URL')
    error = None
    week_events = {}
    week_dates = get_week_dates()
    
    if webcal_url:
        # Fetch and parse calendar data
        ical_content = fetch_webcal_data(webcal_url)
        if ical_content:
            all_events = parse_calendar_events(ical_content)
            week_events = filter_events_for_week(all_events, week_dates)
        else:
            error = "Failed to fetch calendar data. Please check your webcal URL."
    else:
        error = "WEBCAL_URL environment variable not configured."
    
    return render_template('calendar.html', 
                         week_dates=week_dates,
                         week_events=week_events,
                         error=error,
                         today=dt.date.today(),
                         format_event_time=format_event_time)

@app.route('/api/calendar/events')
def api_calendar_events():
    """API endpoint to get calendar events"""
    webcal_url = os.getenv('WEBCAL_URL')
    
    if not webcal_url:
        return jsonify({'error': 'WEBCAL_URL environment variable not configured'}), 400
    
    # Fetch and parse calendar data
    ical_content = fetch_webcal_data(webcal_url)
    if not ical_content:
        return jsonify({'error': 'Failed to fetch calendar data'}), 500
    
    all_events = parse_calendar_events(ical_content)
    
    # Convert events to JSON-serializable format
    json_events = []
    for event in all_events:
        json_event = {
            'uid': event['uid'],
            'summary': event['summary'],
            'description': event['description'],
            'location': event['location'],
            'all_day': event['all_day']
        }
        
        # Convert dates to ISO format
        if isinstance(event['start'], dt.datetime):
            json_event['start'] = event['start'].isoformat()
            json_event['end'] = event['end'].isoformat()
        else:
            json_event['start'] = event['start'].isoformat()
            json_event['end'] = event['end'].isoformat()
            
        json_events.append(json_event)
    
    return jsonify({'events': json_events})

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return {'status': 'healthy', 'timestamp': dt.datetime.now().isoformat()}

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)