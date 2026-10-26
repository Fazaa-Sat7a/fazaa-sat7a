package com.fazaa.customer;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Path;
import android.view.View;
import android.view.animation.LinearInterpolator;

/** Lightweight native flatbed animation. No network, WebView or bitmap downloads. */
public final class TowSplashView extends View {
    private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Path path=new Path();
    private final ValueAnimator animator=ValueAnimator.ofFloat(0f,1f);
    private float phase;
    private boolean loading=true;
    public TowSplashView(Context context){
        super(context);setContentDescription("سطحة فزعة تحمل سيارة");
        animator.setDuration(1600);animator.setRepeatCount(ValueAnimator.INFINITE);animator.setInterpolator(new LinearInterpolator());
        animator.addUpdateListener(value->{phase=(float)value.getAnimatedValue();invalidate();});
    }
    public void setLoading(boolean value){loading=value;sync();}
    private void sync(){if(animator==null)return;if(loading&&isShown()&&getWindowVisibility()==VISIBLE&&ValueAnimator.areAnimatorsEnabled()){if(!animator.isStarted())animator.start();}else animator.cancel();}
    @Override protected void onAttachedToWindow(){super.onAttachedToWindow();sync();}
    @Override protected void onDetachedFromWindow(){animator.cancel();super.onDetachedFromWindow();}
    @Override protected void onVisibilityChanged(View view,int visibility){super.onVisibilityChanged(view,visibility);sync();}
    @Override protected void onWindowVisibilityChanged(int visibility){super.onWindowVisibilityChanged(visibility);sync();}
    private void color(int color){paint.setColor(color);paint.setStyle(Paint.Style.FILL);}
    private void wheel(Canvas canvas,float x,float y){
        color(Color.rgb(20,31,47));canvas.drawCircle(x,y,15,paint);color(Color.rgb(236,241,247));canvas.drawCircle(x,y,8,paint);
        canvas.save();canvas.rotate(phase*360,x,y);paint.setColor(Color.rgb(94,111,131));paint.setStrokeWidth(3);canvas.drawLine(x-6,y,x+6,y,paint);canvas.drawLine(x,y-6,x,y+6,paint);canvas.restore();
    }
    @Override protected void onDraw(Canvas canvas){
        super.onDraw(canvas);float scale=Math.min(getWidth()/320f,getHeight()/190f);canvas.save();canvas.translate((getWidth()-320*scale)/2,(getHeight()-190*scale)/2);canvas.scale(scale,scale);
        color(Color.rgb(225,231,239));canvas.drawRoundRect(12,154,308,161,4,4,paint);
        color(Color.rgb(175,189,207));for(int i=0;i<9;i++){float x=i*44-phase*44;canvas.drawRoundRect(x,171,x+22,174,2,2,paint);}
        canvas.save();canvas.translate(0,(float)Math.sin(phase*Math.PI*4)*1.3f);
        color(Color.rgb(255,184,0));canvas.drawRoundRect(27,124,224,138,4,4,paint);
        path.reset();path.moveTo(222,95);path.lineTo(268,95);path.lineTo(293,122);path.lineTo(293,142);path.lineTo(218,142);path.close();canvas.drawPath(path,paint);
        color(Color.rgb(35,53,74));canvas.drawRoundRect(230,101,263,119,4,4,paint);
        color(Color.rgb(255,247,215));canvas.drawRoundRect(282,124,294,131,3,3,paint);
        color(Color.rgb(54,75,99));path.reset();path.moveTo(49,106);path.lineTo(67,83);path.lineTo(144,83);path.lineTo(166,105);path.lineTo(188,108);path.lineTo(193,122);path.lineTo(40,122);path.lineTo(42,110);path.close();canvas.drawPath(path,paint);
        color(Color.rgb(214,234,244));path.reset();path.moveTo(72,88);path.lineTo(106,88);path.lineTo(106,105);path.lineTo(58,105);path.close();canvas.drawPath(path,paint);path.reset();path.moveTo(113,88);path.lineTo(141,88);path.lineTo(158,105);path.lineTo(113,105);path.close();canvas.drawPath(path,paint);
        color(Color.rgb(20,31,47));canvas.drawCircle(66,121,10,paint);canvas.drawCircle(163,121,10,paint);color(Color.WHITE);canvas.drawCircle(66,121,5,paint);canvas.drawCircle(163,121,5,paint);
        wheel(canvas,73,143);wheel(canvas,249,143);canvas.restore();canvas.restore();
    }
}
