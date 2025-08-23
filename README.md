# Home Calendar

A simple weekly calendar display optimized for iPad 1 that shows events from iCloud webcal sources.

## Project Structure

- `backend/` - Simple Flask application with server-side rendering
- `templates/` - HTML templates for calendar and settings pages

## Development

### Prerequisites
- Docker
- Docker Compose

### Running the Application

1. Start the application:
   ```bash
   docker-compose up --build
   ```

2. Access the application:
   - Calendar: http://localhost:9000

3. To run in background:
   ```bash
   docker-compose up -d --build
   ```

4. To stop the application:
   ```bash
   docker-compose down
   ```

### Configuration

1. Open the application in your browser at http://localhost:9000
2. Click the settings button (⚙️) in the top right corner, or go to http://localhost:9000/settings
3. Enter your iCloud webcal URL (found in Calendar app → Calendar settings → Public Calendar)
4. The page will automatically refresh every 10 minutes to show new events

## Features

- Simple table-based weekly calendar view with current day centered
- iCloud webcal integration
- Optimized for iPad 1 (minimal JavaScript, fast rendering)
- Server-side rendering for maximum compatibility
- Auto-refresh every 10 minutes
- Large fonts and touch-friendly interface
- Dark theme for always-on display
