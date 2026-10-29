package local.homecalendar;

import android.app.Activity;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

@SuppressWarnings("deprecation")
public final class MainActivity extends Activity {
    private static final String CALENDAR_URL = "http://192.168.0.30:9000/";
    private WebView calendar;
    private LinearLayout connectionError;

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        FrameLayout root = new FrameLayout(this);
        calendar = new WebView(this);
        calendar.setBackgroundColor(Color.WHITE);
        calendar.getSettings().setJavaScriptEnabled(true);
        calendar.getSettings().setDomStorageEnabled(true);
        calendar.getSettings().setAllowFileAccess(false);
        calendar.getSettings().setAllowContentAccess(false);
        calendar.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return !isCalendarUrl(url);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return !isCalendarUrl(request.getUrl().toString());
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request,
                    WebResourceError error) {
                if (request.isForMainFrame()) {
                    showConnectionError();
                }
            }

            @Override
            public void onReceivedHttpError(WebView view, WebResourceRequest request,
                    WebResourceResponse response) {
                if (request.isForMainFrame()) {
                    showConnectionError();
                }
            }
        });
        root.addView(calendar, new FrameLayout.LayoutParams(-1, -1));

        connectionError = new LinearLayout(this);
        connectionError.setOrientation(LinearLayout.VERTICAL);
        connectionError.setGravity(Gravity.CENTER);
        int padding = (int) (24 * getResources().getDisplayMetrics().density);
        connectionError.setPadding(padding, padding, padding, padding);
        connectionError.setBackgroundColor(Color.WHITE);

        TextView message = new TextView(this);
        message.setText("Cannot connect to Home Calendar.\n\nCheck Wi-Fi and that the calendar server is running.");
        message.setTextSize(20);
        message.setTextColor(Color.DKGRAY);
        message.setGravity(Gravity.CENTER);
        connectionError.addView(message);

        Button retry = new Button(this);
        retry.setText("Retry");
        retry.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                loadCalendar(CALENDAR_URL);
            }
        });
        connectionError.addView(retry);
        root.addView(connectionError, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);
        enterFullscreen();

        String url = state == null ? CALENDAR_URL : state.getString("calendarUrl", CALENDAR_URL);
        loadCalendar(isCalendarUrl(url) ? url : CALENDAR_URL);
    }

    private static boolean isCalendarUrl(String url) {
        if (url == null) {
            return false;
        }
        Uri uri = Uri.parse(url);
        return "http".equals(uri.getScheme())
                && "192.168.0.30".equals(uri.getHost()) && uri.getPort() == 9000;
    }

    private void loadCalendar(String url) {
        connectionError.setVisibility(View.GONE);
        calendar.setVisibility(View.VISIBLE);
        calendar.loadUrl(url);
    }

    private void showConnectionError() {
        calendar.setVisibility(View.GONE);
        connectionError.setVisibility(View.VISIBLE);
    }

    private void enterFullscreen() {
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            enterFullscreen();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        state.putString("calendarUrl", calendar.getUrl());
        super.onSaveInstanceState(state);
    }

    @Override
    protected void onResume() {
        super.onResume();
        calendar.onResume();
    }

    @Override
    protected void onPause() {
        calendar.onPause();
        super.onPause();
    }

    @Override
    public void onBackPressed() {
        if (connectionError.getVisibility() != View.VISIBLE && calendar.canGoBack()) {
            calendar.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onDestroy() {
        ((FrameLayout) calendar.getParent()).removeView(calendar);
        calendar.destroy();
        super.onDestroy();
    }
}
