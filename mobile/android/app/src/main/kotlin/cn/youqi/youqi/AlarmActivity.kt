package cn.youqi.youqi

import android.app.Activity
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.*
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.*
import java.time.LocalTime
import java.time.format.DateTimeFormatter

/** Native lock-screen UI, available before Flutter finishes starting. */
class AlarmActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var root: LinearLayout
    private lateinit var clock: TextView
    private lateinit var title: TextView
    private lateinit var detail: TextView
    private lateinit var badge: TextView
    private lateinit var footer: TextView
    private val buttons = mutableListOf<Button>()
    private var rendered = ""
    private var busyUntil = 0L
    private var retries = 0
    private fun dp(n: Int) = (resources.displayMetrics.density * n).toInt()
    private fun blend(a: Int, b: Int, ratio: Float): Int = Color.rgb(
        (Color.red(a) * (1-ratio) + Color.red(b) * ratio).toInt(),
        (Color.green(a) * (1-ratio) + Color.green(b) * ratio).toInt(),
        (Color.blue(a) * (1-ratio) + Color.blue(b) * ratio).toInt())
    private fun glass(fill: Int, stroke: Int) = GradientDrawable().apply {
        setColor(fill); cornerRadius = dp(28).toFloat(); setStroke(dp(1), stroke)
    }
    private fun label(text: String, size: Float) = TextView(this).apply {
        this.text = text; textSize = size; gravity = Gravity.CENTER
        setPadding(dp(8),dp(8),dp(8),dp(8))
    }
    private val tick = object : Runnable {
        override fun run() {
            val p = AlarmService.current()
            if (p == null) {
                if (rendered.isNotEmpty() || retries++ > 8) { finish(); return }
            } else {
                retries = 0
                val id = p.optString("fireKey")
                if (rendered != id) {
                    rendered = id; busyUntil = 0
                    title.text = p.optString("title", "时间到了")
                    val count = p.optInt("snoozeCount", p.optInt("attempt",0))
                    val level = AlarmPolicy.level(count)
                    badge.text = "有期 · 正在响铃  /  $level 级"
                    detail.text = if (count == 0) "给现在一个开始" else "已延后 $count 次 · 颜色深度 $level / 7"
                    recolor(level)
                }
                buttons.forEach { it.isEnabled = System.currentTimeMillis() >= busyUntil }
            }
            clock.text = LocalTime.now().format(DateTimeFormatter.ofPattern("HH:mm"))
            handler.postDelayed(this,250)
        }
    }
    private fun recolor(level: Int) {
        val appearance = AlarmHub.state(this).optJSONObject("appearance")
        val accent = when (appearance?.optString("layout")) {
            "b" -> Color.rgb(113,85,187)
            "c" -> Color.rgb(173,116,51)
            else -> Color.rgb(49,91,214)
        }
        val dark = when (appearance?.optString("mode")) {
            "dark" -> true
            "light" -> false
            else -> resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES
        }
        val start = if (dark) blend(accent,Color.BLACK,.55f) else blend(accent,Color.WHITE,.88f)
        val end = blend(accent,Color.BLACK,if(dark).85f else .65f)
        val bg = blend(start,end,(level-1)/6f)
        root.background = GradientDrawable(GradientDrawable.Orientation.TL_BR,
            intArrayOf(bg,blend(bg,accent,.12f),blend(bg,Color.BLACK,.06f)))
        val foreground = if (dark || level >= 4) Color.WHITE else Color.rgb(23,35,56)
        listOf(clock,title,detail,badge,footer).forEach { it.setTextColor(foreground) }
        val useGlass = appearance?.optBoolean("glass",true) != false
        val panelFill = if (useGlass) 0x24ffffff else if(dark || level>=4) 0xff253047.toInt() else Color.WHITE
        val panel = title.parent as LinearLayout
        panel.background = glass(panelFill, if(useGlass)0x70ffffff else Color.TRANSPARENT)
        buttons.forEachIndexed { i,b ->
            b.setTextColor(if(i==0) Color.WHITE else foreground)
            b.background = glass(if(i==0) blend(accent,Color.BLACK,.18f) else panelFill,if(useGlass)0x70ffffff else Color.TRANSPARENT)
        }
        window.statusBarColor = bg; window.navigationBarColor = bg
        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = if(!dark && level<4) View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR else 0
    }
    override fun onCreate(saved: Bundle?) {
        super.onCreate(saved)
        if (Build.VERSION.SDK_INT >= 27) { setShowWhenLocked(true); setTurnScreenOn(true) }
        else window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val scroll = ScrollView(this).apply {
            isFillViewport = true; clipToPadding = false
            setOnApplyWindowInsetsListener { v,insets ->
                // Target 35 may enforce edge-to-edge: reserve room for bars/cutouts.
                @Suppress("DEPRECATION")
                v.setPadding(insets.systemWindowInsetLeft,insets.systemWindowInsetTop,insets.systemWindowInsetRight,insets.systemWindowInsetBottom)
                insets
            }
        }
        root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL; gravity = Gravity.CENTER
            setPadding(dp(24),dp(24),dp(24),dp(24))
        }
        badge = label("有期 · 正在读取提醒",14f); root.addView(badge)
        clock = label("",72f).apply { typeface = Typeface.create("sans-serif-light",Typeface.NORMAL) }
        root.addView(clock,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=dp(24) })
        val panel = LinearLayout(this).apply { orientation=LinearLayout.VERTICAL;setPadding(dp(12),dp(22),dp(12),dp(22)) }
        title = label("时间到了",26f).apply { typeface = Typeface.DEFAULT_BOLD }; panel.addView(title)
        detail = label("",14f); panel.addView(detail)
        root.addView(panel,LinearLayout.LayoutParams(-1,-2).apply { bottomMargin=dp(32) })
        fun button(text: String, action: String) {
            val b = Button(this).apply {
                this.text=text; textSize=17f; isAllCaps=false; minHeight=dp(60)
                setOnClickListener {
                    val p=AlarmService.current() ?: return@setOnClickListener
                    if(p.optString("fireKey")!=rendered || System.currentTimeMillis()<busyUntil)return@setOnClickListener
                    busyUntil=System.currentTimeMillis()+1200
                    buttons.forEach { it.isEnabled=false }
                    startService(Intent(this@AlarmActivity,AlarmService::class.java).setAction(action).putExtra("fireKey",rendered))
                }
            }
            buttons.add(b)
            root.addView(b,LinearLayout.LayoutParams(-1,dp(64)).apply { bottomMargin=dp(12) })
        }
        button("关闭本次","stop")
        button("延后 5 分钟","snooze5")
        button("延后 10 分钟","snooze10")
        footer=label("关闭只结束本次响铃，后续计划照常提醒",12f); root.addView(footer)
        scroll.addView(root,FrameLayout.LayoutParams(-1,-1)); setContentView(scroll)
        recolor(1); handler.post(tick)
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); super.onDestroy() }
}
