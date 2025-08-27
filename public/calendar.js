// Global variables that need to be set from the server
let currentTimeMinutes = 0;
let pageRefreshMinutes = 1;
let isTodayVisible = false;

// Initialize calendar when DOM is loaded
document.addEventListener('DOMContentLoaded', function() {
    // Only scroll to current time if today is visible in the view
    if (isTodayVisible) {
        const currentHour = Math.floor(currentTimeMinutes / 60);
        const scrollTop = Math.max(0, (currentHour - 5) * 60) + 70;

        setTimeout(function() {
            window.scrollTo(0, scrollTop);
        }, 300);
    }
});

// Update current time line every minute
setInterval(function() {
    const now = new Date();
    const minutes = now.getHours() * 60 + now.getMinutes();
    const currentTimeLine = document.querySelector('.current-time-line');

    if (currentTimeLine) {
        currentTimeLine.style.top = minutes + 'px';
    }
}, 60000);

// Auto-refresh page
setTimeout(function() {
    window.location.reload();
}, pageRefreshMinutes * 60 * 1000);

// Function to set variables from server
function setCalendarConfig(config) {
    currentTimeMinutes = config.currentTimeMinutes || 0;
    pageRefreshMinutes = config.pageRefreshMinutes || 1;
    isTodayVisible = config.isTodayVisible || false;
}
