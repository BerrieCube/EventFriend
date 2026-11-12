package nl.eventfriend.eventfriend

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Startscherm-widget: je volgende (of lopende) klus. */
class NextJobWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_next_job).apply {
                setTextViewText(R.id.next_title, widgetData.getString("next_title", "Open EventFriend"))
                val time = widgetData.getString("next_time", "") ?: ""
                setTextViewText(R.id.next_time, time)
                setViewVisibility(R.id.next_time, if (time.isEmpty()) View.GONE else View.VISIBLE)
                val loc = widgetData.getString("next_loc", "") ?: ""
                setTextViewText(R.id.next_loc, loc)
                setViewVisibility(R.id.next_loc, if (loc.isEmpty()) View.GONE else View.VISIBLE)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
