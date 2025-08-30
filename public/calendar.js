document.addEventListener('DOMContentLoaded', function() {
    if (!window.config.isTodayVisible) return;

    const currentHour = Math.floor(window.config.currentTimeMinutes / 60);
    const scrollTop = Math.max(0, (currentHour - 5) * 60) + 70;

    setTimeout(function() {
        window.scrollTo(0, scrollTop);
    }, 300);
});

setInterval(function() {
    const now = new Date();
    const minutes = now.getHours() * 60 + now.getMinutes();
    const currentTimeLine = document.querySelector('.current-time-line');

    if (currentTimeLine) {
        currentTimeLine.style.top = minutes + 'px';
    }
}, 60000);

setTimeout(function() {
    window.location.reload();
}, window.config.pageRefreshMinutes * 60 * 1000);
