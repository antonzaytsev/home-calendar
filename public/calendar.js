var TEMPLATES = {
  calendarBodyWrapper:
    '<div class="calendar-body-wrapper">' +
      '<div class="calendar-body">' +
        '<div class="calendar-row">' +
          '{timeColumn}{dayColumns}'+
        '</div>' +
      '</div>' +
    '</div>',
  dayColumn: '<div class="day-column">' +
               '<div class="hour-grid">{hourGrid}</div>' +
               '{currentTimeIndicator}' +
             '</div>',
  timeColumn: '<div class="time-column">{timeSlots}</div>',
  calendarHeader:
    '<div class="calendar-header">' +
      '<div class="header-row">' +
        '<div class="time-header"></div>' +
        '{dayHeaders}' +
      '</div>' +
    '</div>',
  event:
    '<div class="event{pastClass}" style="top: {topPos}px; height: {height}px; left: {leftPercent}%; width: {widthPercent}%;">' +
      '<div class="event-title">{title}</div>' +
      '<div class="event-time">{timeString}</div>' +
      '<div class="event-location{locationClass}">📍 {location}</div>' +
    '</div>',
  footer: '<div class="footer">Последнее обновление: {lastUpdate} | Автообновление каждые {updateEveryMinutes} минут</div>',
}

var calendar = {
  currentDate: new Date(),
  daysInPast: 1,
  daysInFuture: 2,
  totalDays: 4,
  refreshPagePeriodSeconds: 60,
  events: {},
  eventsLoaded: false,
  lastKnownDate: null, // Track the last known current date for day change detection

  // Russian translations
  monthNames: [null, 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'],
  abbrDayNames: ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'],
  translations: {
    'All Day': 'Весь день',
    'No Title': 'Без названия'
  }
}

function getUrlParameter(name) {
    var search = window.location.search.substring(1);
    var params = search.split('&');
    for (var i = 0; i < params.length; i++) {
        var param = params[i].split('=');
        if (param[0] === name) {
            return decodeURIComponent(param[1]);
        }
    }
    return null;
}

function parseDate(dateString) {
  // ES3-compatible date parsing for YYYY-MM-DD format
  if (!dateString) {
    return new Date();
  }

  var parts = dateString.split('-');
  if (parts.length !== 3) {
    return new Date();
  }

  var year = parseInt(parts[0], 10);
  var month = parseInt(parts[1], 10) - 1; // Month is 0-based in JavaScript
  var day = parseInt(parts[2], 10);

  // Validate the parts
  if (isNaN(year) || isNaN(month) || isNaN(day)) {
    return new Date();
  }

  if (year < 1970 || year > 2100 || month < 0 || month > 11 || day < 1 || day > 31) {
    return new Date();
  }

  return new Date(year, month, day);
}

function getWeekDates() {
    var startDay = new Date(calendar.currentDate);
    startDay.setDate(startDay.getDate() - calendar.daysInPast);

    var dates = [];
    for (var i = 0; i < calendar.totalDays; i++) {
        var currentDay = new Date(startDay);
        currentDay.setDate(startDay.getDate() + i);
        dates.push(currentDay);
    }
    return dates;
}

function formatDate(date) {
    var year = date.getFullYear();
    var month = ('0' + (date.getMonth() + 1)).slice(-2);
    var day = ('0' + date.getDate()).slice(-2);
    return year + '-' + month + '-' + day;
}

function isToday(date) {
    var today = new Date();
    return date.getFullYear() === today.getFullYear() &&
           date.getMonth() === today.getMonth() &&
           date.getDate() === today.getDate();
}

function isWeekend(date) {
    return date.getDay() === 0 || date.getDay() === 6;
}

function getUniqueMonths(dates) {
    var months = [];
    for (var i = 0; i < dates.length; i++) {
        var month = dates[i].getMonth();
        var found = false;
        for (var j = 0; j < months.length; j++) {
            if (months[j] === month) {
                found = true;
                break;
            }
        }
        if (!found) {
            months.push(month);
        }
    }
    return months;
}

function generateHeader(weekDates) {
    var firstDate = weekDates[0];
    var lastDate = weekDates[weekDates.length - 1];

    var currentReferenceDate = weekDates[calendar.daysInPast];
    var prevWeekDate = new Date(currentReferenceDate);
    prevWeekDate.setDate(prevWeekDate.getDate() - calendar.totalDays);
    var nextWeekDate = new Date(currentReferenceDate);
    nextWeekDate.setDate(nextWeekDate.getDate() + calendar.totalDays);

    var months = getUniqueMonths([firstDate, lastDate]);
    var monthDisplayParts = [];
    for (var i = 0; i < months.length; i++) {
        monthDisplayParts.push(calendar.monthNames[months[i] + 1]);
    }
    var monthDisplay = monthDisplayParts.join('-');

    return '<div class="header">' +
                '<div class="header-nav">' +
                    '<button class="nav-button" onclick="calendarPrev()" title="Предыдущие дни">‹ назад</button>' +
                    '<button class="nav-button" onclick="calendarToday()" title="На сегодня" style="margin-left: 8px;">сегодня</button>' +
                '</div>' +
                '<h1>' + monthDisplay + ' ' + firstDate.getFullYear() + '</h1>' +
                '<div class="header-nav">' +
                    '<button class="nav-button" onclick="calendarNext()" title="Следующие дни">вперед ›</button>' +
                '</div>' +
            '</div>';
}

function generateCalendarHeader(weekDates) {
    var dayHeaders = '';
    for (var i = 0; i < weekDates.length; i++) {
        var date = weekDates[i];
        var todayClass = isToday(date) ? ' today' : '';
        var weekendClass = isWeekend(date) ? ' weekend' : '';

        dayHeaders += '<div class="day-header' + todayClass + weekendClass + '">' +
                        '<div class="day-name">' + calendar.abbrDayNames[date.getDay()].toUpperCase() + ' ' + date.getDate() + '</div>' +
                      '</div>';
    }

  return formatTemplate(
    'calendarHeader',
    {dayHeaders: dayHeaders}
  )
}

function generateTimeColumn() {
    var timeSlots = '';
    for (var hour = 0; hour <= 23; hour++) {
        timeSlots += '<div class="time-slot">' + hour + ':00</div>';
    }

  return formatTemplate(
    'timeColumn',
    {timeSlots: timeSlots}
  )
}

function generateDayColumn(date) {
    var today = new Date();
    var currentTimeIndicator = isToday(date) ?
        '<div class="current-time-line" style="top: ' + (today.getHours() * 60 + today.getMinutes()) + 'px;"></div>' : '';

    var hourGrid = '';
    for (var hour = 0; hour <= 23; hour++) {
        hourGrid += '<div class="hour-line"><div class="half-hour-line"></div></div>';
    }

    return formatTemplate(
      'dayColumn',
      {hourGrid: hourGrid, currentTimeIndicator: currentTimeIndicator}
    )
}

function generateCalendarBody(weekDates) {
    var dayColumns = '';
    for (var i = 0; i < weekDates.length; i++) {
        dayColumns += generateDayColumn(weekDates[i]);
    }

  return formatTemplate(
    'calendarBodyWrapper',
    {timeColumn: generateTimeColumn(), dayColumns: dayColumns}
  )
}

function generateFooter() {
    var now = new Date();
    var day = ('0' + now.getDate()).slice(-2);
    var month = ('0' + (now.getMonth() + 1)).slice(-2);
    var year = now.getFullYear();
    var hours = ('0' + now.getHours()).slice(-2);
    var minutes = ('0' + now.getMinutes()).slice(-2);
    var timeString = day + '.' + month + '.' + year + ' ' + hours + ':' + minutes;

    return formatTemplate('footer', { lastUpdate: timeString, updateEveryMinutes: calendar.refreshPagePeriodSeconds / 60 })
}

function hasToday(weekDates) {
    for (var i = 0; i < weekDates.length; i++) {
        if (isToday(weekDates[i])) {
            return true;
        }
    }
    return false;
}

function renderCalendar() {
    var weekDates = getWeekDates();
    var container = document.getElementsByClassName('calendar-container')[0];

    if (!container) {
        // Extra fallback
        var containers = document.getElementsByTagName('div');
        for (var i = 0; i < containers.length; i++) {
            if (containers[i].className === 'calendar-container') {
                container = containers[i];
                break;
            }
        }
    }

    if (container) {
        container.innerHTML = generateHeader(weekDates) +
                             generateCalendarHeader(weekDates) +
                             generateCalendarBody(weekDates) +
                             generateFooter();
    }

    // Auto-scroll to current time if today is visible
    if (hasToday(weekDates)) {
        var currentHour = new Date().getHours();
        var scrollTop = Math.max(0, (currentHour - 5) * 60) + 70;
        setTimeout(function() {
            window.scrollTo(0, scrollTop);
        }, 300);
    }
}

function updateUrl() {
    var weekDates = getWeekDates();
    var referenceDate = weekDates[calendar.daysInPast];
    var dateString = formatDate(referenceDate);

    try {
        if (window.history && window.history.pushState) {
            var newUrl = window.location.protocol + '//' + window.location.host + window.location.pathname;

            if (!isToday(calendar.currentDate)) {
              newUrl += '?date=' + dateString
            }
            window.history.pushState({}, '', newUrl);
        }
    } catch (e) {
        // Ignore history errors on old devices
    }
}

function startTimeUpdater() {
    setInterval(function() {
        var now = new Date();
        var minutes = now.getHours() * 60 + now.getMinutes();
        var currentTimeLine = document.getElementsByClassName('current-time-line')[0];

        if (currentTimeLine) {
            currentTimeLine.style.top = minutes + 'px';
        }
    }, 60000); // Update every minute
}

function calendarPrev() {
    var date = new Date(calendar.currentDate);
    date.setDate(date.getDate() - calendar.totalDays);
    calendar.currentDate = date;

    updateUrl();
    renderCalendar();
    loadEventsForCurrentWeek();
}

function calendarNext() {
    var date = new Date(calendar.currentDate);
    date.setDate(date.getDate() + calendar.totalDays);
    calendar.currentDate = date;

    updateUrl();
    renderCalendar();
    loadEventsForCurrentWeek();
}

function calendarToday() {
    calendar.currentDate = new Date();
    updateUrl();
    renderCalendar();
    loadEventsForCurrentWeek();
}

// ES3-compatible AJAX function
function createXMLHttpRequest() {
    if (window.XMLHttpRequest) {
        return new XMLHttpRequest();
    } else if (window.ActiveXObject) {
        // For older IE versions
        try {
            return new ActiveXObject('Microsoft.XMLHTTP');
        } catch (e) {
            return null;
        }
    }
    return null;
}

function loadEvents(startDate, endDate, callback) {
    var xhr = createXMLHttpRequest();
    if (!xhr) {
        if (callback) callback(null, 'AJAX not supported');
        return;
    }

    var url = '/events?start_date=' + formatDate(startDate) + '&end_date=' + formatDate(endDate);

    xhr.open('GET', url, true);
    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                try {
                    var data = JSON.parse(xhr.responseText);
                    if (callback) callback(data, null);
                } catch (e) {
                    if (callback) callback(null, 'Invalid JSON response');
                }
            } else {
                if (callback) callback(null, 'HTTP error: ' + xhr.status);
            }
        }
    };
    xhr.send();
}

function loadEventsForCurrentWeek() {
    var weekDates = getWeekDates();
    var startDate = weekDates[0];
    var endDate = weekDates[weekDates.length - 1];

    loadEvents(startDate, endDate, function(data, error) {
        if (error) {
            // Show error in footer or ignore silently
            return;
        }

        if (data && data.events) {
            calendar.events = data.events;
            calendar.eventsLoaded = true;
            renderCalendarWithEvents();
        }
    });
}

function renderCalendarWithEvents() {
    var weekDates = getWeekDates();
    var container = document.getElementsByClassName('calendar-container')[0];

    if (!container) {
        var containers = document.getElementsByTagName('div');
        for (var i = 0; i < containers.length; i++) {
            if (containers[i].className === 'calendar-container') {
                container = containers[i];
                break;
            }
        }
    }

    if (container) {
        container.innerHTML = generateHeader(weekDates) +
                             generateCalendarHeader(weekDates) +
                             generateCalendarBodyWithEvents(weekDates) +
                             generateFooter();
    }

    // Auto-scroll to current time if today is visible
    if (hasToday(weekDates)) {
        var currentHour = new Date().getHours();
        var scrollTop = Math.max(0, (currentHour - 5) * 60) + 70;
        setTimeout(function() {
            window.scrollTo(0, scrollTop);
        }, 300);
    }
}

function generateCalendarBodyWithEvents(weekDates) {
    var dayColumns = '';
    for (var i = 0; i < weekDates.length; i++) {
        dayColumns += generateDayColumnWithEvents(weekDates[i]);
    }

    return formatTemplate(
        'calendarBodyWrapper',
        {timeColumn: generateTimeColumn(), dayColumns: dayColumns}
    );
}

function generateDayColumnWithEvents(date) {
    var today = new Date();
    var currentTimeIndicator = isToday(date) ?
        '<div class="current-time-line" style="top: ' + (today.getHours() * 60 + today.getMinutes()) + 'px;"></div>' : '';

    var hourGrid = '';
    for (var hour = 0; hour <= 23; hour++) {
        hourGrid += '<div class="hour-line"><div class="half-hour-line"></div></div>';
    }

    // Add events for this date
    var eventsHtml = generateEventsForDate(date);

    return formatTemplate(
        'dayColumn',
        {hourGrid: hourGrid, currentTimeIndicator: currentTimeIndicator + eventsHtml}
    );
}

function generateEventsForDate(date) {
    var dateKey = formatDate(date);
    var dayEvents = calendar.events[dateKey] || [];

    if (dayEvents.length === 0) {
        return '';
    }

    var allDayEvents = [];
    var timedEvents = [];

    for (var i = 0; i < dayEvents.length; i++) {
        if (dayEvents[i].all_day) {
            allDayEvents.push(dayEvents[i]);
        } else {
            timedEvents.push(dayEvents[i]);
        }
    }

    var eventsHtml = '';

    // Render all-day events
    for (var i = 0; i < allDayEvents.length; i++) {
        eventsHtml += generateAllDayEvent(allDayEvents[i], i);
    }

    // Calculate layout for overlapping timed events
    var eventsWithLayout = calculateEventsLayout(timedEvents);

    // Render timed events with layout
    for (var i = 0; i < eventsWithLayout.length; i++) {
        eventsHtml += generateTimedEventWithLayout(eventsWithLayout[i]);
    }

    return eventsHtml;
}

function generateAllDayEvent(event, index) {
    var isPast = isEventPast(event);
    var pastClass = isPast ? ' past-event' : '';

    return '<div class="event all-day-event' + pastClass + '" style="top: ' + (index * 22) + 'px;">' +
               '<div class="event-title">' + (event.summary || calendar.translations['No Title']) + '</div>' +
               (event.location ? '<div class="event-location">📍 ' + event.location + '</div>' : '') +
           '</div>';
}

function calculateEventsLayout(timedEvents) {
  const widthPercent = 98

    if (timedEvents.length === 0) {
        return [];
    }

    // Sort events by start time
    var sortedEvents = timedEvents.slice().sort(function(a, b) {
        var startA = new Date(a.start);
        var startB = new Date(b.start);
        return startA.getTime() - startB.getTime();
    });

    var eventsWithLayout = [];
    var columns = [];

    for (var i = 0; i < sortedEvents.length; i++) {
        var event = sortedEvents[i];

        var columnIndex = -1;
        for (var j = 0; j < columns.length; j++) {
            var canFit = true;
            for (var k = 0; k < columns[j].length; k++) {
                var existingEvent = columns[j][k];
                if (eventsOverlap(event, existingEvent)) {
                    canFit = false;
                    break;
                }
            }
            if (canFit) {
                columnIndex = j;
                break;
            }
        }

        if (columnIndex === -1) {
            columns.push([]);
            columnIndex = columns.length - 1;
        }

        columns[columnIndex].push(event);

        var totalColumns = columns.length;
        var width = (widthPercent / totalColumns);
        var left = 1 + (columnIndex * (widthPercent / totalColumns));

        eventsWithLayout.push({
            event: event,
            layout: {
                width: width,
                left: left,
                column: columnIndex,
                totalColumns: totalColumns
            }
        });
    }

    var finalColumnCount = columns.length;

    for (var i = 0; i < eventsWithLayout.length; i++) {
        var currentEvent = eventsWithLayout[i].event;
        var hasOverlaps = false;

        for (var j = 0; j < sortedEvents.length; j++) {
            if (sortedEvents[j] !== currentEvent && eventsOverlap(currentEvent, sortedEvents[j])) {
                hasOverlaps = true;
                break;
            }
        }

        var layout = eventsWithLayout[i].layout;

        if (hasOverlaps) {
            layout.width = widthPercent / finalColumnCount;
            layout.left = 1 + (layout.column * (widthPercent / finalColumnCount));
            layout.totalColumns = finalColumnCount;
            layout.hasOverlaps = true;
        } else {
            layout.width = null;
            layout.left = null;
            layout.totalColumns = 1;
            layout.hasOverlaps = false;
        }
    }

    return eventsWithLayout;
}

function eventsOverlap(event1, event2) {
    var start1 = new Date(event1.start);
    var end1 = new Date(event1.end);
    var start2 = new Date(event2.start);
    var end2 = new Date(event2.end);

    return start1 < end2 && start2 < end1;
}

function generateTimedEventWithLayout(eventWithLayout) {
    var event = eventWithLayout.event;
    var layout = eventWithLayout.layout;
    var isPast = isEventPast(event);
    var pastClass = isPast ? ' past-event' : '';

    var topPos = getEventTopPosition(event) + 1;
    var height = getEventHeight(event) - 2;

    if (layout.width === null && layout.left === null) {
        return '<div class="event' + pastClass + '" style="top: ' + topPos + 'px; height: ' + height + 'px;">' +
               '<div class="event-title">' + (event.summary || calendar.translations['No Title']) + '</div>' +
               '<div class="event-time">' + formatEventTime(event) + '</div>' +
               '<div class="event-location hide">' + (event.location || '') + '</div>' +
               '</div>';
    }

    var leftPercent = layout.left;
    var widthPercent = layout.width;

    return formatTemplate(
      'event',
      {
        pastClass: pastClass,
        topPos: topPos,
        height: height,
        leftPercent: leftPercent,
        widthPercent: widthPercent,
        title: event.summary || calendar.translations['No Title'],
        timeString: formatEventTime(event),
        // location: event.location,
        // locationClass: event.location ? '' : ' hide'
        locationClass: ' hide'
      }
    )
}

function isEventPast(event) {
    var now = new Date();
    var today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    if (event.all_day) {
        var eventDate = parseDate(event.start.split('T')[0]);
        return eventDate < today;
    } else {
        var eventEnd = new Date(event.end);
        return eventEnd < now;
    }
}

function getEventTopPosition(event) {
    if (event.all_day) return 0;

    try {
        var startTime = new Date(event.start);
        return startTime.getHours() * 60 + startTime.getMinutes();
    } catch (e) {
        return 0;
    }
}

function getEventHeight(event) {
    if (event.all_day) return 20;

    try {
        var startTime = new Date(event.start);
        var endTime = new Date(event.end);
        var startMinutes = startTime.getHours() * 60 + startTime.getMinutes();
        var endMinutes = endTime.getHours() * 60 + endTime.getMinutes();
        var duration = endMinutes - startMinutes;
        return Math.max(duration, 20);
    } catch (e) {
        return 20;
    }
}

function formatEventTime(event) {
    if (event.all_day) return calendar.translations['All Day'];

    try {
        var startTime = new Date(event.start);
        var endTime = new Date(event.end);
        var startStr = ('0' + startTime.getHours()).slice(-2) + ':' + ('0' + startTime.getMinutes()).slice(-2);
        var endStr = ('0' + endTime.getHours()).slice(-2) + ':' + ('0' + endTime.getMinutes()).slice(-2);
        return startStr + ' - ' + endStr;
    } catch (e) {
        return calendar.translations['All Day'];
    }
}

function checkForDayChange() {
    var today = new Date();
    var todayDateString = formatDate(today);

    if (!calendar.lastKnownDate) {
        calendar.lastKnownDate = todayDateString;
        return false;
    }

    if (calendar.lastKnownDate !== todayDateString) {
        calendar.lastKnownDate = todayDateString;
        return true;
    }

    return false;
}

function handleDayChange() {
    calendar.currentDate = new Date();
    updateUrl();
    renderCalendar();
    loadEventsForCurrentWeek();
}

function startPeriodicEventUpdates() {
    setInterval(function() {
        if (checkForDayChange()) {
            handleDayChange();
        } else {
            loadEventsForCurrentWeek();
        }
    }, calendar.refreshPagePeriodSeconds * 1000);
}

function initCalendar() {
    var dateParam = getUrlParameter('date');
    if (dateParam) {
        try {
            calendar.currentDate = parseDate(dateParam);
        } catch (e) {
            calendar.currentDate = new Date();
        }
    }

    var today = new Date();
    calendar.lastKnownDate = formatDate(today);

    renderCalendar();
    loadEventsForCurrentWeek();
    startTimeUpdater();
    startPeriodicEventUpdates();
}

function formatTemplate(templateName, variables) {
  var html = TEMPLATES[templateName]
  if (html === undefined) {
    alert('no such template ' + templateName)
    html = ''
  }
  for (var key in variables) {
    html = html.replace("{" + key + "}", variables[key])
  }

  return html
}

if (document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
        initCalendar();
    });
} else {
    window.onload = function() {
        initCalendar();
    };
}
