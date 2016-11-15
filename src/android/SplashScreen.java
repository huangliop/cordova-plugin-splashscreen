/*
       Licensed to the Apache Software Foundation (ASF) under one
       or more contributor license agreements.  See the NOTICE file
       distributed with this work for additional information
       regarding copyright ownership.  The ASF licenses this file
       to you under the Apache License, Version 2.0 (the
       "License"); you may not use this file except in compliance
       with the License.  You may obtain a copy of the License at

         http://www.apache.org/licenses/LICENSE-2.0

       Unless required by applicable law or agreed to in writing,
       software distributed under the License is distributed on an
       "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
       KIND, either express or implied.  See the License for the
       specific language governing permissions and limitations
       under the License.
*/

package org.apache.cordova.splashscreen;

import android.app.Dialog;
import android.app.ProgressDialog;
import android.content.Context;
import android.content.DialogInterface;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.net.Uri;
import android.os.CountDownTimer;
import android.os.Handler;
import android.util.Log;
import android.view.Display;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup.LayoutParams;
import android.view.WindowManager;
import android.view.animation.Animation;
import android.view.animation.AlphaAnimation;
import android.view.animation.DecelerateInterpolator;
import android.widget.Button;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.RelativeLayout;
import android.widget.TextView;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaWebView;
import org.json.JSONArray;
import org.json.JSONException;

import java.io.File;
import java.util.Date;

public class SplashScreen extends CordovaPlugin {
    private static final String LOG_TAG = "SplashScreen";
    // Cordova 3.x.x has a copy of this plugin bundled with it (SplashScreenInternal.java).
    // Enable functionality only if running on 4.x.x.
    private static final boolean HAS_BUILT_IN_SPLASH_SCREEN = Integer.valueOf(CordovaWebView.CORDOVA_VERSION.split("\\.")[0]) < 4;
    private static final int DEFAULT_SPLASHSCREEN_DURATION = 3000;
    private static Dialog splashDialog;
    private static ProgressDialog spinnerDialog;
    private static boolean firstShow = true;
    private static boolean lastHideAfterDelay; // https://issues.apache.org/jira/browse/CB-9094

    /**
     * Displays the splash drawable.
     */
    private ImageView splashImageView;

    /**
     * Remember last device orientation to detect orientation changes.
     */
    private int orientation;

    // Helper to be compile-time compatible with both Cordova 3.x and 4.x.
    private View getView() {
        try {
            return (View)webView.getClass().getMethod("getView").invoke(webView);
        } catch (Exception e) {
            return (View)webView;
        }
    }

    @Override
    protected void pluginInitialize() {
        if (HAS_BUILT_IN_SPLASH_SCREEN) {
            return;
        }
        // Make WebView invisible while loading URL
        getView().setVisibility(View.INVISIBLE);
        int drawableId = preferences.getInteger("SplashDrawableId", 0);
        if (drawableId == 0) {
            String splashResource = preferences.getString("SplashScreen", "screen");
            if (splashResource != null) {
                drawableId = cordova.getActivity().getResources().getIdentifier(splashResource, "drawable", cordova.getActivity().getClass().getPackage().getName());
                if (drawableId == 0) {
                    drawableId = cordova.getActivity().getResources().getIdentifier(splashResource, "drawable", cordova.getActivity().getPackageName());
                }
                preferences.set("SplashDrawableId", drawableId);
            }
        }

        // Save initial orientation.
        orientation = cordova.getActivity().getResources().getConfiguration().orientation;

        if (firstShow) {
            boolean autoHide = preferences.getBoolean("AutoHideSplashScreen", true);
            showSplashScreen(autoHide);
        }

        if (preferences.getBoolean("SplashShowOnlyFirstTime", true)) {
            firstShow = false;
        }
    }

    /**
     * Shorter way to check value of "SplashMaintainAspectRatio" preference.
     */
    private boolean isMaintainAspectRatio () {
        return preferences.getBoolean("SplashMaintainAspectRatio", false);
    }

    private int getFadeDuration () {
        int fadeSplashScreenDuration = preferences.getBoolean("FadeSplashScreen", true) ?
            preferences.getInteger("FadeSplashScreenDuration", DEFAULT_SPLASHSCREEN_DURATION) : 0;

        if (fadeSplashScreenDuration < 30) {
            // [CB-9750] This value used to be in decimal seconds, so we will assume that if someone specifies 10
            // they mean 10 seconds, and not the meaningless 10ms
            fadeSplashScreenDuration *= 1000;
        }

        return fadeSplashScreenDuration;
    }

    @Override
    public void onPause(boolean multitasking) {
        if (HAS_BUILT_IN_SPLASH_SCREEN) {
            return;
        }
        // hide the splash screen to avoid leaking a window
        this.removeSplashScreen(true);
    }

    @Override
    public void onDestroy() {
        if (HAS_BUILT_IN_SPLASH_SCREEN) {
            return;
        }
        // hide the splash screen to avoid leaking a window
        this.removeSplashScreen(true);
        // If we set this to true onDestroy, we lose track when we go from page to page!
        //firstShow = true;
    }

    @Override
    public boolean execute(String action, JSONArray args, CallbackContext callbackContext) throws JSONException {
        if (action.equals("hide")) {
            cordova.getActivity().runOnUiThread(new Runnable() {
                public void run() {
                    webView.postMessage("splashscreen", "hide");
                }
            });
        } else if (action.equals("show")) {
            cordova.getActivity().runOnUiThread(new Runnable() {
                public void run() {
                    webView.postMessage("splashscreen", "show");
                }
            });
        } else {
            return false;
        }

        callbackContext.success();
        return true;
    }

    @Override
    public Object onMessage(String id, Object data) {
        if (HAS_BUILT_IN_SPLASH_SCREEN) {
            return null;
        }
        if ("splashscreen".equals(id)) {
            if ("hide".equals(data.toString())) {
                this.removeSplashScreen(false);
            } else {
                this.showSplashScreen(false);
            }
        } else if ("spinner".equals(id)) {
            if ("stop".equals(data.toString())) {
                getView().setVisibility(View.VISIBLE);
            }
        } else if ("onReceivedError".equals(id)) {
            this.spinnerStop();
        }
        return null;
    }

    // Don't add @Override so that plugin still compiles on 3.x.x for a while
    public void onConfigurationChanged(Configuration newConfig) {
        if (newConfig.orientation != orientation) {
            orientation = newConfig.orientation;

            // Splash drawable may change with orientation, so reload it.
            if (splashImageView != null) {
                int drawableId = preferences.getInteger("SplashDrawableId", 0);
                if (drawableId != 0) {
                    splashImageView.setImageDrawable(cordova.getActivity().getResources().getDrawable(drawableId));
                }
            }
        }
    }

    private void removeSplashScreen(final boolean forceHideImmediately) {
        cordova.getActivity().runOnUiThread(new Runnable() {
            public void run() {
                if (splashDialog != null && splashDialog.isShowing()) {
                    final int fadeSplashScreenDuration = getFadeDuration();
                    // CB-10692 If the plugin is being paused/destroyed, skip the fading and hide it immediately
                    if (fadeSplashScreenDuration > 0 && forceHideImmediately == false) {
                        AlphaAnimation fadeOut = new AlphaAnimation(1, 0);
                        fadeOut.setInterpolator(new DecelerateInterpolator());
                        fadeOut.setDuration(fadeSplashScreenDuration);

                        splashImageView.setAnimation(fadeOut);
                        splashImageView.startAnimation(fadeOut);

                        fadeOut.setAnimationListener(new Animation.AnimationListener() {
                            @Override
                            public void onAnimationStart(Animation animation) {
                                spinnerStop();
                            }

                            @Override
                            public void onAnimationEnd(Animation animation) {
                                if (splashDialog != null && splashDialog.isShowing()) {
                                    splashDialog.dismiss();
                                    splashDialog = null;
                                    splashImageView = null;
                                }
                            }

                            @Override
                            public void onAnimationRepeat(Animation animation) {
                            }
                        });
                    } else {
                        spinnerStop();
                        splashDialog.dismiss();
                        splashDialog = null;
                        splashImageView = null;
                    }
                }
            }
        });
    }

    /**
     * Shows the splash screen over the full Activity
     */
    @SuppressWarnings("deprecation")
    private void showSplashScreen(final boolean hideAfterDelay) {
        final int splashscreenTime = preferences.getInteger("SplashScreenDelay", DEFAULT_SPLASHSCREEN_DURATION);
        final int drawableId = preferences.getInteger("SplashDrawableId", 0);

        File adsPath=new File(webView.getContext().getCacheDir()+"/ads");
        String imageName="ad.jpg";
        int adDuration=0;
        //获取ads目录下的第一个文件
        if(adsPath.listFiles()!=null&&adsPath.listFiles().length!=0){
            //获取广告图片的名称
            imageName=adsPath.listFiles()[adsPath.listFiles().length-1].getName();
            Log.d(LOG_TAG,"get file :"+imageName);
            try {
                //获取广告图片持续时间
                adDuration=Integer.parseInt(imageName.split("_|\\.")[3])*1000;
            } catch (Exception e) {
                adDuration=0;
            }
        }
        //图片是否在有效期内
        final boolean available=isAvailable(imageName);
        if(!available)adDuration=0;//如果图片不在有效期内，就恢复之前显示时长
        final int fadeSplashScreenDuration = getFadeDuration();
        final int effectiveSplashDuration = Math.max(adDuration, splashscreenTime - fadeSplashScreenDuration);

        lastHideAfterDelay = hideAfterDelay;

        // If the splash dialog is showing don't try to show it again
        if (splashDialog != null && splashDialog.isShowing()) {
            return;
        }
        if (drawableId == 0 || (splashscreenTime <= 0 && hideAfterDelay)) {
            return;
        }

        //如果该目录存在广告图片，则将启动页替换为该广告图
        final Uri imageUri=Uri.parse(webView.getContext().getCacheDir()+"/ads/"+imageName);

        cordova.getActivity().runOnUiThread(new Runnable() {
            public void run() {
                // Get reference to display
                Display display = cordova.getActivity().getWindowManager().getDefaultDisplay();
                Context context = webView.getContext();

                splashImageView = new ImageView(webView.getContext());
                // Use an ImageView to render the image because of its flexible scaling options.

                File imageFile=new File(String.valueOf(imageUri));
                if(imageFile.length()<1000)imageFile.delete();
                if(imageFile.exists()&&available){
                    splashImageView.setImageURI(imageUri);
                }else {
                    splashImageView.setImageResource(drawableId);
                }
                LayoutParams layoutParams = new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT);
                splashImageView.setLayoutParams(layoutParams);

                splashImageView.setMinimumHeight(display.getHeight());
                splashImageView.setMinimumWidth(display.getWidth());

                // TODO: Use the background color of the webView's parent instead of using the preference.
                splashImageView.setBackgroundColor(preferences.getInteger("backgroundColor", Color.BLACK));

                if (isMaintainAspectRatio()) {
                    // CENTER_CROP scale mode is equivalent to CSS "background-size:cover"
                    splashImageView.setScaleType(ImageView.ScaleType.CENTER_CROP);
                }
                else {
                    // FIT_XY scales image non-uniformly to fit into image view.
                    splashImageView.setScaleType(ImageView.ScaleType.FIT_XY);
                }

                // Create and show the dialog
                splashDialog = new Dialog(context, android.R.style.Theme_Translucent_NoTitleBar);
                // check to see if the splash screen should be full screen
                if ((cordova.getActivity().getWindow().getAttributes().flags & WindowManager.LayoutParams.FLAG_FULLSCREEN)
                        == WindowManager.LayoutParams.FLAG_FULLSCREEN) {
                    splashDialog.getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                            WindowManager.LayoutParams.FLAG_FULLSCREEN);
                }
                if(imageFile.exists()){
                    RelativeLayout relativeLayout=makeParentView(splashImageView);
                    splashDialog.setContentView(relativeLayout);
                    makeSeconds(relativeLayout,effectiveSplashDuration/1000);
                }else {
                    splashDialog.setContentView(splashImageView);
                }
                splashDialog.setCancelable(false);
                splashDialog.show();

                if (preferences.getBoolean("ShowSplashScreenSpinner", true)) {
                    spinnerStart();
                }

                // Set Runnable to remove splash screen just in case
                if (hideAfterDelay) {
                    final Handler handler = new Handler();
                    handler.postDelayed(new Runnable() {
                        public void run() {
                            if (lastHideAfterDelay) {
                                removeSplashScreen(false);
                            }
                        }
                    }, effectiveSplashDuration);
                }
            }
        });
    }

    /**
     * 创建广告图片的父容器
     * @return RelativeLayout
     */
    private RelativeLayout makeParentView(View view){
        RelativeLayout relativeLayout=new RelativeLayout(cordova.getActivity());
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT,LayoutParams.MATCH_PARENT);
        relativeLayout.setLayoutParams(params);

        relativeLayout.addView(view);
        addSkipBtn(relativeLayout);
        return relativeLayout;
    }

    /**
     * 添加跳过按钮
     * @param layout
     * @return
     */
    private void addSkipBtn(RelativeLayout layout){
        Button btn=new Button(cordova.getActivity());
        RelativeLayout.LayoutParams params=new RelativeLayout.LayoutParams(LayoutParams.WRAP_CONTENT,LayoutParams.WRAP_CONTENT);
        params.addRule(RelativeLayout.ALIGN_PARENT_RIGHT);

        btn.setPadding(10,10,10,10);
        btn.setText("跳过");
        btn.setBackgroundColor(Color.TRANSPARENT);
        btn.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {

                removeSplashScreen(true);
            }
        });
        layout.addView(btn,params);
    }

    // Show only spinner in the center of the screen
    private void spinnerStart() {
        cordova.getActivity().runOnUiThread(new Runnable() {
            public void run() {
                spinnerStop();

                spinnerDialog = new ProgressDialog(webView.getContext());
                spinnerDialog.setOnCancelListener(new DialogInterface.OnCancelListener() {
                    public void onCancel(DialogInterface dialog) {
                        spinnerDialog = null;
                    }
                });

                spinnerDialog.setCancelable(false);
                spinnerDialog.setIndeterminate(true);

                RelativeLayout centeredLayout = new RelativeLayout(cordova.getActivity());
                centeredLayout.setGravity(Gravity.CENTER);
                centeredLayout.setLayoutParams(new RelativeLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT));

                ProgressBar progressBar = new ProgressBar(webView.getContext());
                RelativeLayout.LayoutParams layoutParams = new RelativeLayout.LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT);
                layoutParams.addRule(RelativeLayout.CENTER_IN_PARENT, RelativeLayout.TRUE);
                progressBar.setLayoutParams(layoutParams);

                centeredLayout.addView(progressBar);

                spinnerDialog.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
                spinnerDialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));

                spinnerDialog.show();
                spinnerDialog.setContentView(centeredLayout);
            }
        });
    }

    private void spinnerStop() {
        cordova.getActivity().runOnUiThread(new Runnable() {
            public void run() {
                if (spinnerDialog != null && spinnerDialog.isShowing()) {
                    spinnerDialog.dismiss();
                    spinnerDialog = null;
                }
            }
        });
    }

    /**
     * 根据文件名称判断广告是否在有效期内
     * @param fileName
     * @return
     */
    private boolean isAvailable(String fileName){
        String[] ss=fileName.split("_");
        //如果图片名称没有带有效时间端参数，就直接显示图片
        if(ss.length==1)return true;
        try {
            long startTime=Long.parseLong(ss[1]);
            long endTime=Long.parseLong(ss[2]);
            Date now=new Date();
            if(now.getTime()<endTime&&now.getTime()>startTime)return true;
        } catch (Exception e) {
            e.printStackTrace();
        }
        return false;
    }

    /**
     * 创建倒计时
     * @param layout
     */
    private void makeSeconds(RelativeLayout layout,int seconds){
        TextView lable=new TextView(webView.getContext());
        lable.setText(seconds+"s");
        lable.setTextSize(20);
        lable.setTextColor(Color.WHITE);
        lable.setPadding(20,15,10,10);
        layout.addView(lable);
        startCountdown((seconds+1)*1000,lable);
    }
    private void startCountdown(int millis , final TextView lable){
        new CountDownTimer(millis,1000){

            @Override
            public void onTick(long millisUntilFinished) {
                lable.setText((millisUntilFinished/1000)+"s");
            }

            @Override
            public void onFinish() {
            }
        }.start();
    }
}
