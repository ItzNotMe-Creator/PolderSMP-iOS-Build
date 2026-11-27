package nl.poldersmp.control;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Bundle;
import android.content.Intent;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.graphics.Color;
import android.net.Uri;
import android.view.View;
import android.view.WindowManager;
import android.webkit.*;
import android.widget.*;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.io.InputStream;
import javax.net.ssl.HttpsURLConnection;
import org.json.JSONObject;

public class MainActivity extends Activity {
    private WebView web;
    private TextView brand, status;
    private LinearLayout root;
    private String origin, clientStyle;
    private boolean failed;
    private final android.os.Handler retry=new android.os.Handler(android.os.Looper.getMainLooper());
    private final Runnable reconnect=new Runnable(){public void run(){if(!paused&&failed&&origin!=null)openPanel();retry.postDelayed(this,8000);}};
    private boolean locked = false, paused = false;
    private ValueCallback<Uri[]> fileChooser;
    private static final int FILE_PICK=771;
    private int generation = 0;
    private static final int BG = 0xff101827, FG = 0xffeef3fb;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        getWindow().setStatusBarColor(BG); getWindow().setNavigationBarColor(BG);
        origin = normalize(getPreferences(0).getString("origin",""));
        try (InputStream in = getAssets().open("client-style.js")) {
            clientStyle = new String(readBytes(in), StandardCharsets.UTF_8);
        } catch (Exception e) { clientStyle = null; }
        root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(BG);
        LinearLayout bar = new LinearLayout(this); bar.setGravity(android.view.Gravity.CENTER_VERTICAL);
        bar.setPadding(dp(16),dp(6),dp(8),dp(6));
        brand = new TextView(this); brand.setText("PolderSMP"); brand.setTextColor(FG); brand.setTextSize(19);brand.setTypeface(android.graphics.Typeface.DEFAULT,android.graphics.Typeface.BOLD);
        ImageView logo=new ImageView(this);logo.setImageResource(nl.poldersmp.control.R.drawable.polder_brand);logo.setScaleType(ImageView.ScaleType.FIT_CENTER);LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(dp(30),dp(30));lp.setMarginEnd(dp(10));bar.addView(logo,lp);
        bar.addView(brand,new LinearLayout.LayoutParams(0,dp(48),1));
        TextView refresh=new TextView(this);refresh.setText("↻");refresh.setTextColor(FG);refresh.setTextSize(25);refresh.setGravity(android.view.Gravity.CENTER);refresh.setContentDescription("Vernieuwen");refresh.setOnClickListener(v->{if(origin!=null)openPanel();});bar.addView(refresh,new LinearLayout.LayoutParams(dp(44),dp(48)));
        Button connection = new Button(this); connection.setText("Koppel"); connection.setOnClickListener(v -> {
            if (origin == null) editAddress(null);
            else web.evaluateJavascript("typeof owner === 'function' && owner() ? key : ''", value -> {
                try { String token = (String)new org.json.JSONTokener(value).nextValue();
                    if (!token.isEmpty()) verifyOwner(token);
                    else new AlertDialog.Builder(this).setMessage("Log in als hoofdeigenaar om het adres te wijzigen. Bij verbindingsproblemen kun je de koppeling lokaal wissen.").setPositiveButton("OK",null).setNeutralButton("Koppeling wissen",(d,w)->resetAddress()).show();
                } catch(Exception ignored) {}
            });
        });
        bar.addView(connection); root.addView(bar);
        status = new TextView(this); status.setTextColor(0xff9fc4ff);status.setTextSize(13); status.setPadding(dp(16),dp(12),dp(16),dp(12)); root.addView(status);
        web = new WebView(this); web.setBackgroundColor(BG);
        WebSettings s = web.getSettings(); s.setJavaScriptEnabled(true); s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false); s.setAllowContentAccess(false); s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        s.setCacheMode(WebSettings.LOAD_NO_CACHE);s.setJavaScriptCanOpenWindowsAutomatically(false);s.setSupportMultipleWindows(false);
        web.setWebChromeClient(new WebChromeClient(){
            @Override public boolean onShowFileChooser(WebView w,ValueCallback<Uri[]> cb,FileChooserParams params){
                if(fileChooser!=null)fileChooser.onReceiveValue(null);
                fileChooser=cb;
                try{startActivityForResult(params.createIntent(),FILE_PICK);}
                catch(Exception e){fileChooser.onReceiveValue(null);fileChooser=null;}
                return true;
            }
        });
        web.setWebViewClient(new WebViewClient(){
            @Override public boolean shouldOverrideUrlLoading(WebView w, WebResourceRequest r) { return !sameOrigin(r.getUrl().toString()); }
            @Override public void onPageStarted(WebView w,String url,android.graphics.Bitmap icon){if(sameOrigin(url)){failed=false;showStatus("Verbinden…");}}
            @Override public void onPageFinished(WebView w,String url){if(sameOrigin(url)&&!failed){if(clientStyle!=null)w.evaluateJavascript(clientStyle,null);showStatus("");}}
            @Override public void onReceivedError(WebView w, WebResourceRequest r, WebResourceError e) { if(r.isForMainFrame()){failed=true;showStatus("Niet verbonden · controleer Tailscale. Opnieuw proberen…");} }
            @Override public void onReceivedHttpError(WebView w,WebResourceRequest r,WebResourceResponse e){if(r.isForMainFrame()){failed=true;showStatus("Server antwoordt met HTTP "+e.getStatusCode());}}
            @Override public void onReceivedSslError(WebView w, android.webkit.SslErrorHandler h, android.net.http.SslError e) { h.cancel(); failed=false; showStatus("HTTPS-certificaat ongeldig. Controleer Tailscale."); }
        });
        root.addView(web,new LinearLayout.LayoutParams(-1,0,1)); setContentView(root);
        if(origin != null) openPanel(); else showStatus("Open een koppellink of tik op Verbinding. Zorg dat Tailscale verbonden is.");
        handlePair(getIntent());retry.postDelayed(reconnect,8000);
    }
    private static byte[] readBytes(InputStream in) throws java.io.IOException {
        java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int count;
        while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
        return out.toByteArray();
    }
    private int dp(int n){ return (int)(getResources().getDisplayMetrics().density*n+.5f); }
    private void showStatus(String s){ status.setText(s); status.setVisibility(s.isEmpty()?View.GONE:View.VISIBLE); }
    private String normalize(String text){
        try { text=text.trim(); if(text.isEmpty()) return null; if(!text.contains("://")) text="https://"+text;
            URI u=new URI(text); String host=u.getHost();
            if(!"https".equalsIgnoreCase(u.getScheme())||host==null||!host.toLowerCase(java.util.Locale.ROOT).endsWith(".ts.net")||u.getUserInfo()!=null||u.getQuery()!=null||u.getFragment()!=null||!(u.getPath().isEmpty()||u.getPath().equals("/"))||u.getPort()>65535||u.getPort()==0)return null;
            return "https://"+host.toLowerCase(java.util.Locale.ROOT)+(u.getPort()==-1?"":":"+u.getPort());
        }catch(Exception e){return null;}
    }
    private boolean sameOrigin(String url){try { URI u=new URI(url); return origin!=null && origin.equals(normalize(new URI(u.getScheme(),u.getAuthority(),"/",null,null).toString())); }catch(Exception e){return false;}}
    private void openPanel(){
        locked=false; failed=false; showStatus("Verbinden…");
        web.setVisibility(View.VISIBLE); web.loadUrl(origin+"/");
    }
    private void handlePair(Intent i){
        Uri u=i.getData(); if(u!=null && origin==null && "poldersmp".equals(u.getScheme()) && "koppel".equals(u.getHost()))editAddress(u.getQueryParameter("adres"));
    }
    @Override protected void onNewIntent(Intent i){super.onNewIntent(i);setIntent(i);handlePair(i);}
    private void resetAddress(){generation++; web.evaluateJavascript("if(typeof lockPanel==='function')lockPanel()",null); origin=null; getPreferences(0).edit().remove("origin").apply(); web.loadUrl("about:blank"); web.setVisibility(View.INVISIBLE); showStatus("Koppeling gewist. Tik op Verbinding.");}
    private void editAddress(String suggested){
        EditText input=new EditText(this);input.setSingleLine(true);input.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_VARIATION_URI);input.setText(suggested!=null?suggested:origin);
        new AlertDialog.Builder(this).setTitle("Verbinding").setMessage("Privé HTTPS-adres van de server-pc (inclusief poort).").setView(input)
            .setNegativeButton("Annuleren",null).setNeutralButton("Kopieer koppellink",(d,w)->{
                if(origin!=null){ClipboardManager cm=(ClipboardManager)getSystemService(CLIPBOARD_SERVICE);cm.setPrimaryClip(ClipData.newPlainText("PolderSMP","poldersmp://koppel?adres="+Uri.encode(origin)));}})
            .setPositiveButton("Adres opslaan",(d,w)->{String next=normalize(input.getText().toString()); if(next==null){showStatus("Gebruik een geldig HTTPS-adres van Tailscale.");return;} probe(next);}).show();
    }
    private JSONObject request(String base,String path,String token,boolean post)throws Exception{
        HttpsURLConnection c=(HttpsURLConnection)new java.net.URL(base+path).openConnection();
        try {c.setInstanceFollowRedirects(false);c.setConnectTimeout(8000);c.setReadTimeout(8000);if(token!=null)c.setRequestProperty("Authorization","Bearer "+token);
            if(post){c.setRequestMethod("POST");c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json");try(java.io.OutputStream out=c.getOutputStream()){out.write("{}".getBytes(StandardCharsets.UTF_8));}}
            if(c.getResponseCode()!=200)throw new java.io.IOException("HTTP "+c.getResponseCode());
            try(InputStream in=c.getInputStream()){return new JSONObject(new String(readBytes(in),StandardCharsets.UTF_8));}
        }finally{c.disconnect();}
    }
    private void probe(String next){int epoch=++generation;showStatus("Verbinding controleren…");new Thread(()->{
        try{JSONObject j=request(next,"/api/login-info",null,true);if(!(j.opt("setup") instanceof Boolean)||!(j.opt("needsStation") instanceof Boolean))throw new Exception("Onbekend paneel");
            runOnUiThread(()->{if(epoch!=generation||paused)return;web.evaluateJavascript("if(typeof lockPanel==='function')lockPanel()",null);origin=next;getPreferences(0).edit().putString("origin",origin).apply();openPanel();});
        }catch(Exception e){runOnUiThread(()->{if(epoch==generation)showStatus("Koppelen mislukt: "+e.getMessage()+". Controleer Tailscale.");});}
    }).start();}
    private void verifyOwner(String token){String base=origin;int epoch=generation;new Thread(()->{
        try{JSONObject j=request(base,"/api/access",token,false);runOnUiThread(()->{if(epoch==generation&&!paused&&"owner".equals(j.optString("role")))editAddress(null);});}
        catch(Exception e){runOnUiThread(()->showStatus("Eigenaarstoegang niet bevestigd."));}
    }).start();}
    @Override protected void onStop(){super.onStop();paused=true;generation++;}
    @Override protected void onStart(){super.onStart();paused=false;if(web!=null&&origin!=null)web.evaluateJavascript("if(typeof refresh==='function')refresh()",null);}
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);if(request==FILE_PICK&&fileChooser!=null){fileChooser.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result,data));fileChooser=null;}}
    @Override protected void onDestroy(){retry.removeCallbacks(reconnect);if(fileChooser!=null){fileChooser.onReceiveValue(null);fileChooser=null;}if(web!=null)web.destroy();super.onDestroy();}
}
