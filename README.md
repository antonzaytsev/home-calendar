# Home Calendar

A simple weekly calendar display that shows events from iCloud webcal sources, specifically designed to run on iPad 1st generation.

## What it is

A Ruby Sinatra web application that displays your calendar events in a clean weekly view with Russian localization. The main idea is to run this app on iPad 1st generation, which is very old and doesn't support modern JavaScript and CSS. That's why it uses server-side rendering, minimal JavaScript, and simple HTML/CSS for maximum compatibility with legacy devices.

## How to start it

1. Set your iCloud webcal URL in a `.env` file:
   ```
   WEBCAL_URL=your_ical_url_here
   ```

2. Start with Docker:
   ```bash
   docker-compose up --build
   ```

3. Open http://localhost:9000 in your browser

4. To stop:
   ```bash
   docker-compose down
   ```
