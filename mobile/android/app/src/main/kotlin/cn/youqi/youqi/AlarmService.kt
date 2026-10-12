package cn.youqi.youqi

import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.media.*
import android.net.Uri
import android.os.*
import org.json.JSONObject
import java.util.ArrayDeque

/** Audio and vibration stay native, even when the Flutter process has no visible page. */
class AlarmService:Service(){
    companion object {
        private var live:AlarmService?=null
        fun current():JSONObject?=live?.active
        fun reconcileActive(c:Context){live?.handler?.post{live?.prune()}}
        fun cancelKey(key:String){live?.handler?.post{live?.let{s->
            s.queue.removeAll{it.optString("key")==key||it.optString("parentKey")==key}
            if(s.active?.let{it.optString("key")==key||it.optString("parentKey")==key}==true)s.advance()
        }}}
    }
    val handler=Handler(Looper.getMainLooper())
    private val queue=ArrayDeque<JSONObject>()
    var active:JSONObject?=null;private set
    private var player:MediaPlayer?=null
    private var wake:PowerManager.WakeLock?=null
    private var vibrator:Vibrator?=null
    private var timeout:Runnable?=null
    private fun foreground(n:Notification){if(Build.VERSION.SDK_INT>=29)startForeground(701,n,ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)else startForeground(701,n)}
    override fun onBind(intent:Intent?):IBinder?=null
    override fun onCreate(){super.onCreate();live=this;AlarmHub.channel(this)}
    private fun actionIntent(action:String,p:JSONObject):PendingIntent {
        val id=p.optString("fireKey")
        return PendingIntent.getService(this,0,Intent(this,AlarmService::class.java).setAction(action)
            .setData(Uri.parse("youqi://action/$action/${Uri.encode(id)}")).putExtra("fireKey",id),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun notification(p:JSONObject,full:Boolean):Notification {
        val options=ActivityOptions.makeBasic()
        if(Build.VERSION.SDK_INT>=34)options.setPendingIntentCreatorBackgroundActivityStartMode(ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED)
        val open=PendingIntent.getActivity(this,0,Intent(this,AlarmActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,options.toBundle())
        val b=Notification.Builder(this,AlarmHub.CHANNEL).setSmallIcon(cn.youqi.youqi.R.drawable.ic_alarm)
            .setContentTitle(p.optString("title","有期提醒")).setContentText(if(full)"时间到了 · 点击查看" else "时间到了")
            .setCategory(Notification.CATEGORY_ALARM).setVisibility(Notification.VISIBILITY_PUBLIC).setOngoing(full).setContentIntent(open)
        if(full){
            b.setFullScreenIntent(open,true).addAction(Notification.Action.Builder(null,"关闭本次",actionIntent("stop",p)).build())
                .addAction(Notification.Action.Builder(null,"延后5分钟",actionIntent("snooze5",p)).build())
                .addAction(Notification.Action.Builder(null,"延后10分钟",actionIntent("snooze10",p)).build())
        }else b.setAutoCancel(true).setContentIntent(PendingIntent.getActivity(this,1,Intent(this,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
        return b.build()
    }
    override fun onStartCommand(intent:Intent?,flags:Int,startId:Int):Int {
        if(intent?.action=="ring"){
            val p=try{JSONObject(intent.getStringExtra("payload")?:"{}")}catch(e:Exception){stopSelf();return START_NOT_STICKY}
            foreground(notification(p,false))
            if(!AlarmHub.valid(this,p)){if(active==null)stopSelf() else foreground(notification(active!!,true));return START_NOT_STICKY}
            if(AlarmHub.state(this).optString("deviceMode","ring")=="notify"){
                getSystemService(NotificationManager::class.java).notify(p.optString("fireKey").hashCode(),notification(p,false))
                if(active==null){stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()} else foreground(notification(active!!,true))
            }else if(active==null){active=p;begin()}else {
                if(active?.optString("fireKey")!=p.optString("fireKey") && queue.none{it.optString("fireKey")==p.optString("fireKey")})queue.add(p)
                foreground(notification(active!!,true))
            }
        }else {
            val p=active
            if(p!=null && intent?.action in listOf("stop","snooze5","snooze10","skip","disable") && AlarmPolicy.acceptsAction(intent?.getStringExtra("fireKey"),p.optString("fireKey"))){
                try {
                when(intent?.action){
                    "snooze5","snooze10"->{
                        val minutes=if(intent.action=="snooze5")5 else 10
                        if(!AlarmHub.snooze(this,p,minutes)){
                            android.widget.Toast.makeText(this,"延后未成功，请检查精确闹钟权限；当前响铃保留",android.widget.Toast.LENGTH_LONG).show()
                            return START_NOT_STICKY
                        }
                    }
                    "skip"->AlarmHub.skipNext(this,p)
                    "disable"->AlarmHub.disable(this,p)
                }
                if(intent?.action !in listOf("snooze5","snooze10"))AlarmHub.log(this,p.optString("title"),when(intent?.action){"skip"->"关闭本次并跳过下次";"disable"->"停用整个提醒规则";else->"关闭本次"})
                advance()
                }catch(e:Exception){AlarmHub.log(this,p.optString("title"),"操作失败：${e.javaClass.simpleName}");android.widget.Toast.makeText(this,"操作未成功，当前响铃保留",android.widget.Toast.LENGTH_LONG).show()}
            }
            if(p==null)stopSelf()
        }
        return START_NOT_STICKY
    }
    private fun begin(){
        val p=active?:return
        foreground(notification(p,true))
        MainActivity.showActiveAlarmIfVisible()
        val ring=p.optJSONObject("ring")?:JSONObject()
        wake=getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"youqi:alarm").apply{acquire(35*60*1000L)}
        val attrs=AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        val uri=ring.optString("tone").takeIf{it.isNotEmpty()}?.let{Uri.parse(it)}?:RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        fun play(source:Uri){
            val candidate=MediaPlayer()
            try{candidate.apply{
                setAudioAttributes(attrs);setDataSource(this@AlarmService,source);isLooping=true
                val volume=ring.optDouble("volume",.85).toFloat().coerceIn(0f,1f);setVolume(volume,volume)
                prepare();start()
            };player=candidate}catch(e:Exception){candidate.release();throw e}
        }
        try{play(uri)}catch(e:Exception){player?.release();player=null;try{play(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))}catch(e:Exception){AlarmHub.log(this,p.optString("title"),"铃声不可用，请重新选择铃声")}}
        if(ring.optBoolean("vibrate",true)){
            vibrator=if(Build.VERSION.SDK_INT>=31)getSystemService(VibratorManager::class.java).defaultVibrator else getSystemService(Vibrator::class.java)
            vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0,500,300,500,1000),0),attrs)
        }
        timeout=Runnable{
            if(ring.optBoolean("autoRepeat",false))AlarmHub.snooze(this,p)
            AlarmHub.log(this,p.optString("title"),"响铃时长结束");advance()
        }.also{handler.postDelayed(it,ring.optLong("duration",60).coerceIn(10,1800)*1000)}
    }
    private fun stopAudio(){
        timeout?.let{handler.removeCallbacks(it)};timeout=null
        try{player?.stop()}catch(_:Exception){};player?.release();player=null
        vibrator?.cancel();vibrator=null
        if(wake?.isHeld==true)wake?.release();wake=null
    }
    private fun advance(){
        stopAudio();active=null
        while(queue.isNotEmpty()){val p=queue.removeFirst();if(AlarmHub.valid(this,p)){active=p;begin();return}}
        stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()
    }
    private fun prune(){
        if(AlarmHub.state(this).optString("deviceMode","ring")!="ring"){
            queue.clear();stopAudio();active=null;stopForeground(STOP_FOREGROUND_REMOVE);stopSelf();return
        }
        queue.removeAll{!AlarmHub.valid(this,it)}
        val p=active
        if(p!=null && !AlarmHub.valid(this,p))advance()
    }
    override fun onDestroy(){stopAudio();queue.clear();active=null;if(live===this)live=null;super.onDestroy()}
}
