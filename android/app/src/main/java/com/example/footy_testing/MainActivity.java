package com.example.footy_testing;

import androidx.annotation.NonNull;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import android.util.Log;
import com.example.footy_testing.pose.MoveNetHelper;
import com.example.footy_testing.pose.BallDetectionHelper;

public class MainActivity extends FlutterActivity {
    private static final String TAG = "MainActivity";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        try {

            MoveNetHelper.registerWith(flutterEngine, getContext());
            Log.d(TAG, "MoveNetHelper registriert");

            BallDetectionHelper.registerWith(flutterEngine, getContext());
            Log.d(TAG, "BallDetectionHelper registriert");

        } catch (Exception e) {
            Log.e(TAG, "Fehler beim Registrieren der MethodChannels", e);
            e.printStackTrace();
        }
    }
}
