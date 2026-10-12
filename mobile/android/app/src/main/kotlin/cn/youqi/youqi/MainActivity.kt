package cn.youqi.youqi

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.*
import android.content.*
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import org.json.JSONObject
import org.json.JSONArray
import java.util.concurrent.Executors

class MainActivity: FlutterActivity(){
    companion object {
        private var visible: java.lang.ref.WeakReference<MainActivity>? = null
        fun showActiveAlarmIfVisible() {
            val host = visible?.get() ?: return
            host.runOnUiThread {
                if (visible?.get() === host && AlarmService.current() != null && !host.isFinishing) {
                    host.startActivity(Intent(host, AlarmActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                }
            }
        }
    }
    override fun onResume() {
        super.onResume()
        visible = java.lang.ref.WeakReference(this)
        showActiveAlarmIfVisible()
    }
    override fun onPause() {
        if (visible?.get() === this) visible = null
        super.onPause()
    }
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        showActiveAlarmIfVisible()
    }
    private val worker=Executors.newSingleThreadExecutor()
    private var pendingResult:MethodChannel.Result?=null
    private var backup=""
    override fun configureFlutterEngine(engine:FlutterEngine){
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger,"cn.youqi/native").setMethodCallHandler{call,result->
            fun async(block:()->Any?){worker.execute{try{val value=block();runOnUiThread{result.success(value)}}catch(e:Exception){runOnUiThread{result.error("NATIVE",e.message,null)}}}}
            when(call.method){
                "load"->async{AlarmHub.prefs(this).getString("state",null)}
                "save"->async{
                    val root=JSONObject(call.arguments as String)
                    synchronized(AlarmHub){
                        val old=AlarmHub.state(this)
                        // A lock-screen action may have changed state while Flutter was paused.
                        if(root.optInt("nativeGeneration")<old.optInt("nativeGeneration")){
                            for(change in AlarmHub.jsonList(old.optJSONArray("nativeOverrides")?:JSONArray())){
                                val parent=change.optString("parent");val kind=change.optString("sourceKind");val id=change.optString("sourceId")
                                if(kind=="alarm"||kind=="shift")for(item in AlarmHub.jsonList(root.optJSONArray(if(kind=="alarm")"alarms" else "shifts")?:JSONArray()))if(item.optString("id")==id)item.put("enabled",false)
                                if(kind=="task")for(item in AlarmHub.jsonList(root.optJSONArray(if(parent.startsWith("block:"))"blocks" else "tasks")?:JSONArray()))for(r in AlarmHub.jsonList(item.optJSONArray("reminders")?:JSONArray())){
                                    val key=if(parent.startsWith("block:"))"block:${item.optString("id")}:${r.optString("id")}" else "task:${item.optString("id")}:${r.optString("id")}"
                                    if(key==parent)r.put("enabled",false)
                                }
                                for(rule in AlarmHub.jsonList(root.optJSONArray("nativeRules")?:JSONArray()))if(rule.optString("key")==parent)rule.put("enabled",false)
                            }
                            val out=root.optJSONArray("outbox")?:JSONArray();val ids=AlarmHub.jsonList(out).map{it.optString("mutationId")}.toSet()
                            for(m in AlarmHub.jsonList(old.optJSONArray("outbox")?:JSONArray()))if(m.optString("mutationId") !in ids)out.put(m)
                            root.put("outbox",out);root.put("nativeGeneration",old.optInt("nativeGeneration"));root.put("nativeOverrides",old.optJSONArray("nativeOverrides")?:JSONArray())
                        }
                        check(AlarmHub.prefs(this).edit().putString("state",root.toString()).commit()){"写入失败，请检查可用空间"}
                        AlarmHub.reconcile(this)
                    };null
                }
                "status"->async{AlarmHub.reconcile(this);AlarmHub.status(this)}
                "setTodoNotification"->async{synchronized(AlarmHub){TodoNotification.setEnabled(this,call.arguments as Boolean)};null}
                "history"->async{AlarmHub.history(this)}
                "oneShot"->async{AlarmHub.oneShot(this,JSONObject(call.arguments as Map<*,*>));null}
                "cancelOneShot"->async{AlarmHub.cancelShot(this,call.arguments as String);null}
                "permission"->{try{permission(call.arguments as String);result.success(null)}catch(e:Exception){result.error("SETTINGS",e.message,null)}}
                "pickTone","exportBackup","importBackup"->{
                    if(pendingResult!=null){result.error("BUSY","请先关闭已打开的系统选择器",null);return@setMethodCallHandler}
                    pendingResult=result
                    try{when(call.method){
                        "pickTone"->startActivityForResult(Intent(RingtoneManager.ACTION_RINGTONE_PICKER).putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,RingtoneManager.TYPE_ALARM).putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT,false).putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE,"选择闹钟铃声"),901)
                        "exportBackup"->{backup=call.arguments as String;startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("application/json").putExtra(Intent.EXTRA_TITLE,"有期备份-${java.time.LocalDate.now()}.json"),902)}
                        else->startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"),903)
                    }}catch(e:Exception){pendingResult=null;result.error("PICKER",e.message,null)}
                }
                else->result.notImplemented()
            }
        }
    }
    private fun permission(kind:String){
        val uri=Uri.parse("package:$packageName")
        if(kind=="notifications"&&Build.VERSION.SDK_INT>=33){requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"),910);return}
        val action=when(kind){"exact"->if(Build.VERSION.SDK_INT>=31)Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM else Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            "fullScreen"->if(Build.VERSION.SDK_INT>=34)Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT else Settings.ACTION_APPLICATION_DETAILS_SETTINGS
            "battery"->Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
            else->Settings.ACTION_APP_NOTIFICATION_SETTINGS}
        startActivity(Intent(action).apply{if(kind=="battery"){}else if(action==Settings.ACTION_APP_NOTIFICATION_SETTINGS)putExtra(Settings.EXTRA_APP_PACKAGE,packageName)else data=uri})
    }
    @Deprecated("Android compatibility activity result bridge")
    override fun onActivityResult(requestCode:Int,resultCode:Int,data:Intent?){
        super.onActivityResult(requestCode,resultCode,data)
        if(requestCode !in 901..903)return
        val result=pendingResult?:return;pendingResult=null
        if(resultCode!=Activity.RESULT_OK){result.success(null);backup="";return}
        if(requestCode==901){val uri=data?.getParcelableExtra<Uri>(RingtoneManager.EXTRA_RINGTONE_PICKED_URI);result.success(uri?.toString());return}
        val uri=data?.data?:run{result.error("FILE","未选择文件",null);return}
        val text=backup;backup=""
        worker.execute{try{
            val value=if(requestCode==902){contentResolver.openOutputStream(uri,"wt")!!.use{it.write(text.toByteArray(Charsets.UTF_8))};true}else{
                contentResolver.openInputStream(uri)!!.use{input->val out=java.io.ByteArrayOutputStream();val buffer=ByteArray(8192);var count=input.read(buffer);while(count!=-1){require(out.size()+count<=20*1024*1024){"备份超过 20 MB"};out.write(buffer,0,count);count=input.read(buffer)};out.toString("UTF-8")}
            }
            runOnUiThread{result.success(value)}
        }catch(e:Exception){runOnUiThread{result.error("FILE",e.message,null)}}}
    }
}
