const TEMPLATES = {
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
  calendarHeader: '<div class="calendar-header">' +
    '<div class="header-row">' +
    '<div class="time-header"></div>' +
    '{dayHeaders}' +
    '</div>' +
    '</div>',
  footer: '<div class="footer">Последнее обновление: {lastUpdate} | Автообновление каждые {updateEveryMinutes} минут</div>',
}

var calendar = {
  currentDate: new Date(),
  daysInPast: 1,
  daysInFuture: 2,
  totalDays: 4,
  refreshPagePeriodSeconds: 60,

  // Russian translations
  monthNames: [null, 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь', 'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'],
  abbrDayNames: ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб'],
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
        var minutes = now.getHours() * calendar.refreshPagePeriodSeconds + now.getMinutes();
        var currentTimeLine = document.getElementsByClassName('current-time-line')[0];

        if (currentTimeLine) {
            currentTimeLine.style.top = minutes + 'px';
        }
    }, calendar.refreshPagePeriodSeconds * 1000);
}

function calendarPrev() {
    var date = new Date(calendar.currentDate);
    date.setDate(date.getDate() - calendar.totalDays)
    calendar.currentDate = date;

    updateUrl();
    renderCalendar();
}

function calendarNext() {
  var date = new Date(calendar.currentDate);
  date.setDate(date.getDate() + calendar.totalDays)
  calendar.currentDate = date;

    updateUrl();
    renderCalendar();
}

function calendarToday() {
    calendar.currentDate = new Date();
    updateUrl();
    renderCalendar();
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

    renderCalendar();
    startTimeUpdater();
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

// Initialize calendar when DOM is loaded
if (document.addEventListener) {
    document.addEventListener('DOMContentLoaded', function() {
        initCalendar();
    });
} else {
    // Fallback for very old browsers
    window.onload = function() {
        initCalendar();
    };
}
