import { useState, useEffect, useMemo } from 'react'
import { format, startOfWeek, addDays, isSameDay, parseISO, isToday } from 'date-fns'
import axios from 'axios'
import './WeeklyCalendar.css'

const WeeklyCalendar = () => {
  const [events, setEvents] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [currentDate] = useState(new Date())

  // Calculate week days with current day in the center (position 3)
  const weekDays = useMemo(() => {
    const today = new Date()
    const startDay = addDays(today, -3) // Start 3 days before today
    return Array.from({ length: 7 }, (_, index) => addDays(startDay, index))
  }, [])

  const fetchEvents = async () => {
    try {
      setLoading(true)
      setError(null)
      
      const response = await axios.get(`${import.meta.env.VITE_API_URL}/api/calendar/events`)
      
      setEvents(response.data.events || [])
    } catch (err) {
      console.error('Error fetching events:', err)
      setError(err.response?.data?.error || 'Failed to load calendar events. Please check the WEBCAL_URL environment variable.')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchEvents()
    // Refresh events every 5 minutes
    const interval = setInterval(fetchEvents, 5 * 60 * 1000)
    return () => clearInterval(interval)
  }, [])

  const getEventsForDay = (day) => {
    return events.filter(event => {
      const eventStart = parseISO(event.start)
      const eventEnd = parseISO(event.end)
      return isSameDay(eventStart, day) || 
             (eventStart <= day && eventEnd >= day)
    })
  }

  const formatEventTime = (event) => {
    if (event.all_day) return 'All Day'
    
    const start = parseISO(event.start)
    const end = parseISO(event.end)
    return `${format(start, 'HH:mm')} - ${format(end, 'HH:mm')}`
  }

  if (loading && events.length === 0) {
    return (
      <div className="calendar-loading">
        <div className="loading-spinner"></div>
        <p>Loading calendar events...</p>
      </div>
    )
  }

  return (
    <div className="weekly-calendar">
      <div className="calendar-header">
        <h1>
          {format(weekDays[0], 'MMMM yyyy')}
        </h1>
        {error && (
          <div className="error-message">
            {error}
          </div>
        )}
      </div>

      <div className="week-view">
        {weekDays.map((day, index) => {
          const dayEvents = getEventsForDay(day)
          const isCurrentDay = isToday(day)
          
          return (
            <div 
              key={day.toISOString()} 
              className={`day-column ${isCurrentDay ? 'current-day' : ''} ${index === 3 ? 'center-day' : ''}`}
            >
              <div className="day-header">
                <div className="day-name">{format(day, 'EEEE')}</div>
                <div className={`day-number ${isCurrentDay ? 'today' : ''}`}>
                  {format(day, 'd')}
                </div>
              </div>

              <div className="day-events">
                {dayEvents.length === 0 ? (
                  <div className="no-events">No events</div>
                ) : (
                  dayEvents.map((event, eventIndex) => (
                    <div 
                      key={`${event.uid}-${eventIndex}`} 
                      className={`event ${event.all_day ? 'all-day-event' : 'timed-event'}`}
                    >
                      <div className="event-time">
                        {formatEventTime(event)}
                      </div>
                      <div className="event-title">
                        {event.summary}
                      </div>
                      {event.location && (
                        <div className="event-location">
                          📍 {event.location}
                        </div>
                      )}
                    </div>
                  ))
                )}
              </div>
            </div>
          )
        })}
      </div>

      <div className="calendar-footer">
        <div className="last-updated">
          Last updated: {format(new Date(), 'HH:mm')}
        </div>
        {events.length > 0 && (
          <div className="event-count">
            {events.length} events this week
          </div>
        )}
      </div>
    </div>
  )
}

export default WeeklyCalendar
