package nl.eventfriend.eventfriend

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Startscherm-widget: de notitie waarbij "Op widget" aan staat. */
class NoteWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_note).apply {
                setTextViewText(R.id.note_title, widgetData.getString("note_title", "Notitie"))
                setTextViewText(
                    R.id.note_text,
                    widgetData.getString("note_text", "Open een notitie in EventFriend en zet \"Op widget\" aan."),
                )
                setOnClickPendingIntent(
                    R.id.widget_root,
                    HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
                )
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
