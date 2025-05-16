/**
 * Autor: Furkan Kilic
 * 
 * Diese Datei implementiert die Ballerkennung mit dem YOLOv8-Modell für die Footballista-App.
 * Ermöglicht die Erkennung von Fußbällen in Bildern und stellt eine Schnittstelle zwischen 
 * dem Flutter-Framework und den nativen Objekterkennungsfunktionen bereit.
 */

package com.example.footy_testing.pose;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.util.Log;

import androidx.annotation.NonNull;

import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.gpu.GpuDelegate;
import org.tensorflow.lite.support.common.FileUtil;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.*;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class BallDetectionHelper implements MethodChannel.MethodCallHandler {
    private static final String TAG = "BallDetectionHelper";
    private static final String CHANNEL = "com.example.footy_testing/ball_detection";

    private static final int INPUT_SIZE = 640;

    private final Context context;
    private Interpreter yoloInterpreter;
    private GpuDelegate gpuDelegate;
    private List<String> labels;
    private int soccerBallClassId = -1;

    private long frameCount = 0;
    private long totalInferenceTime = 0;
    private double movingAvgInferenceTime = 0;

    public static void registerWith(FlutterEngine flutterEngine, Context context) {
        MethodChannel channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        BallDetectionHelper helper = new BallDetectionHelper(context);
        channel.setMethodCallHandler(helper);
    }

    public BallDetectionHelper(Context context) {
        this.context = context;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "loadModels":
                try {
                    Map<String, Object> args = call.arguments();
                    String modelPath = ((String) args.get("modelPath"));
                    String labelsPath = ((String) args.get("labelsPath"));
                    boolean useGpu = args.containsKey("useGpu") ? (boolean) args.get("useGpu") : false;

                    if (modelPath.startsWith("assets/"))
                        modelPath = modelPath.substring(7);
                    if (labelsPath.startsWith("assets/"))
                        labelsPath = labelsPath.substring(7);

                    Log.d(TAG, "Lade YOLOv8-Modell: " + modelPath);
                    Log.d(TAG, "Lade Labels: " + labelsPath);

                    Interpreter.Options options = new Interpreter.Options();
                    options.setNumThreads(4);

                    if (useGpu) {
                        try {
                            gpuDelegate = new GpuDelegate();
                            options.addDelegate(gpuDelegate);

                            options.setUseNNAPI(false);
                            Log.d(TAG, "GPU-Delegate für YOLOv8 aktiviert");
                        } catch (Exception e) {
                            Log.w(TAG, "GPU-Delegate für YOLOv8 nicht verfügbar: " + e.getMessage());

                            try {
                                options.setUseNNAPI(true);
                                Log.d(TAG, "Fallback auf NNAPI für YOLOv8");
                            } catch (Exception nnError) {
                                Log.w(TAG, "NNAPI auch nicht verfügbar: " + nnError.getMessage());
                            }
                        }
                    } else {
                        try {
                            options.setUseNNAPI(true);
                            Log.d(TAG, "NNAPI für YOLOv8 aktiviert");
                        } catch (Exception e) {
                            Log.w(TAG, "NNAPI konnte nicht aktiviert werden: " + e.getMessage());
                        }
                    }

                    Log.d(TAG, "Verarbeite YOLOv8-Inferenz mit optimierter Konfiguration");

                    try {

                        yoloInterpreter = new Interpreter(FileUtil.loadMappedFile(context, modelPath), options);

                        int[] inputShape = yoloInterpreter.getInputTensor(0).shape();
                        int[] outputShape = yoloInterpreter.getOutputTensor(0).shape();

                        String inputShapeStr = Arrays.toString(inputShape);
                        String outputShapeStr = Arrays.toString(outputShape);

                        Log.d(TAG, "Modell geladen - Eingabeform: " + inputShapeStr);
                        Log.d(TAG, "Modell geladen - Ausgabeform: " + outputShapeStr);

                        labels = FileUtil.loadLabels(context, labelsPath);
                        Log.d(TAG, "Labels geladen: " + labels.size() + " Klassen");

                        for (int i = 0; i < labels.size(); i++) {
                            String label = labels.get(i).toLowerCase();
                            if (label.contains("soccer") || label.contains("sports ball") || label.equals("ball")) {
                                soccerBallClassId = i;
                                Log.d(TAG, "Ball-Klasse gefunden: '" + labels.get(i) + "' mit Index " + i);
                                break;
                            }
                        }

                        if (soccerBallClassId == -1) {
                            Log.w(TAG, "Keine Ball-Klasse in Labels gefunden!");
                        }

                        result.success(true);
                    } catch (Exception e) {

                        Log.e(TAG, "Fehler beim Laden des Modells mit ursprünglichen Optionen: " + e.getMessage());

                        options = new Interpreter.Options();
                        options.setNumThreads(1);

                        try {
                            options.setUseNNAPI(true);
                            Log.d(TAG, "NNAPI für Fallback aktiviert");
                        } catch (Exception nnError) {
                            Log.w(TAG, "NNAPI für Fallback nicht verfügbar");
                        }

                        Log.d(TAG, "Versuche mit minimalster Konfiguration");

                        yoloInterpreter = new Interpreter(FileUtil.loadMappedFile(context, modelPath), options);

                        labels = FileUtil.loadLabels(context, labelsPath);

                        for (int i = 0; i < labels.size(); i++) {
                            String label = labels.get(i).toLowerCase();
                            if (label.contains("soccer") || label.contains("sports ball") || label.equals("ball")) {
                                soccerBallClassId = i;
                                break;
                            }
                        }

                        result.success(true);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "Fehler beim Laden des Modells", e);
                    e.printStackTrace();
                    result.error("LOAD_FAIL", e.getMessage(), null);
                }
                break;

            case "detectBall":
                try {
                    Map<String, Object> args = call.arguments();
                    byte[] yPlane = (byte[]) args.get("imageBytes");
                    byte[] uPlane = args.containsKey("uPlane") ? (byte[]) args.get("uPlane") : null;
                    byte[] vPlane = args.containsKey("vPlane") ? (byte[]) args.get("vPlane") : null;

                    int width = (int) args.get("width");
                    int height = (int) args.get("height");

                    int uvRowStride = args.containsKey("uvRowStride") ? (int) args.get("uvRowStride") : width;
                    int uvPixelStride = args.containsKey("uvPixelStride") ? (int) args.get("uvPixelStride") : 1;

                    int rotation = args.containsKey("rotation") ? (int) args.get("rotation") : 0;
                    boolean isFrontCamera = args.containsKey("isFrontCamera") ? (boolean) args.get("isFrontCamera")
                            : false;

                    Log.d(TAG,
                            "Ball-Erkennung, Bildgröße: " + width + "x" + height + ", Frontkamera: " + isFrontCamera);

                    long startTime = System.currentTimeMillis();

                    Bitmap bitmap;
                    if (uPlane != null && vPlane != null) {
                        bitmap = yuvPlanesToBitmap(yPlane, uPlane, vPlane, width, height, uvRowStride, uvPixelStride);
                    } else {
                        bitmap = yuvToBitmap(yPlane, width, height);
                    }

                    if (bitmap == null) {
                        Log.e(TAG, "Bitmap-Konvertierung fehlgeschlagen");
                        result.error("IMAGE_CONVERSION_ERROR", "Bitmap-Konvertierung fehlgeschlagen", null);
                        return;
                    }

                    if (rotation != 0) {
                        try {

                            Matrix rotationMatrix = new Matrix();
                            rotationMatrix.postRotate(rotation);

                            Bitmap rotatedBitmap = Bitmap.createBitmap(
                                    bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(),
                                    rotationMatrix, true);

                            if (bitmap != rotatedBitmap) {
                                bitmap.recycle();
                            }
                            bitmap = rotatedBitmap;

                            if (rotation == 90 || rotation == 270) {

                                Log.d(TAG, "Verarbeite Bild: " + bitmap.getWidth() + "x" + bitmap.getHeight()
                                        + ", Frontkamera: " + isFrontCamera);
                            }
                        } catch (OutOfMemoryError e) {
                            Log.e(TAG, "Speicherproblem bei der Bildrotation: " + e.getMessage());

                        }
                    }

                    List<Map<String, Object>> detections = detectBall(bitmap, isFrontCamera);

                    long processingTime = System.currentTimeMillis() - startTime;

                    Map<String, Object> resultMap = new HashMap<>();
                    resultMap.put("detections", detections);
                    resultMap.put("processingTimeMs", processingTime);

                    bitmap.recycle();

                    result.success(resultMap);

                } catch (Exception e) {
                    Log.e(TAG, "Fehler bei der Ball-Erkennung", e);
                    e.printStackTrace();

                    Map<String, Object> errorResult = new HashMap<>();
                    errorResult.put("error", e.getMessage());
                    errorResult.put("processingTimeMs", 0);
                    errorResult.put("detections", new ArrayList<>());

                    result.success(errorResult);
                }
                break;

            default:
                result.notImplemented();
                break;
        }
    }

    private List<Map<String, Object>> detectBall(Bitmap bitmap) {
        return detectBall(bitmap, false);
    }

    /**
     * Erkennt einen Ball im Bild mit dem YOLOv8-Modell
     * 
     * @param bitmap        Das zu analysierende Bild
     * @param isFrontCamera Gibt an, ob das Bild von der Frontkamera stammt
     * @return Liste von erkannten Bällen mit Position und Konfidenz
     */
    private List<Map<String, Object>> detectBall(Bitmap bitmap, boolean isFrontCamera) {
        if (yoloInterpreter == null) {
            Log.e(TAG, "YOLO Interpreter ist null");
            return new ArrayList<>();
        }

        try {

            int[] inputShape = yoloInterpreter.getInputTensor(0).shape();
            int modelHeight = inputShape[1];
            int modelWidth = inputShape[2];
            int channels = inputShape[3];

            float ballThreshold = 0.10f;

            Log.d(TAG, "Verarbeite Bild: " + bitmap.getWidth() + "x" + bitmap.getHeight() + ", Frontkamera: "
                    + isFrontCamera);

            Bitmap scaledBitmap = Bitmap.createScaledBitmap(bitmap, modelWidth, modelHeight, true);

            boolean isQuantized = yoloInterpreter.getInputTensor(0).dataType() == org.tensorflow.lite.DataType.UINT8 ||
                    yoloInterpreter.getInputTensor(0).dataType() == org.tensorflow.lite.DataType.INT8;

            ByteBuffer imgData;
            if (isQuantized) {

                imgData = ByteBuffer.allocateDirect(modelWidth * modelHeight * channels);
                imgData.order(ByteOrder.nativeOrder());

                int[] pixels = new int[modelWidth * modelHeight];
                scaledBitmap.getPixels(pixels, 0, modelWidth, 0, 0, modelWidth, modelHeight);

                for (int pixel : pixels) {
                    imgData.put((byte) ((pixel >> 16) & 0xFF));
                    imgData.put((byte) ((pixel >> 8) & 0xFF));
                    imgData.put((byte) (pixel & 0xFF));
                }
            } else {

                imgData = ByteBuffer.allocateDirect(4 * modelWidth * modelHeight * channels);
                imgData.order(ByteOrder.nativeOrder());

                int[] pixels = new int[modelWidth * modelHeight];
                scaledBitmap.getPixels(pixels, 0, modelWidth, 0, 0, modelWidth, modelHeight);

                for (int pixel : pixels) {
                    imgData.putFloat(((pixel >> 16) & 0xFF) / 255.0f);
                    imgData.putFloat(((pixel >> 8) & 0xFF) / 255.0f);
                    imgData.putFloat((pixel & 0xFF) / 255.0f);
                }
            }

            scaledBitmap.recycle();

            imgData.rewind();

            Log.d(TAG, "YOLOv8 Eingabe-Buffer: " + imgData.capacity() + " Bytes");

            int[] outputShape = yoloInterpreter.getOutputTensor(0).shape();
            Log.d(TAG, "YOLOv8 Ausgabe-Form: " + Arrays.toString(outputShape));

            float[][][] output = new float[outputShape[0]][outputShape[1]][outputShape[2]];

            Map<Integer, Object> outputMap = new HashMap<>();
            outputMap.put(0, output);

            long inferenceStartTime = System.currentTimeMillis();

            try {
                yoloInterpreter.runForMultipleInputsOutputs(new Object[] { imgData }, outputMap);

                long inferenceTime = System.currentTimeMillis() - inferenceStartTime;
                Log.d(TAG, "YOLOv8 Inferenzzeit: " + inferenceTime + "ms");

                frameCount++;
                totalInferenceTime += inferenceTime;
                movingAvgInferenceTime = totalInferenceTime / frameCount;
            } catch (Exception e) {
                Log.e(TAG, "Fehler bei der Inferenz: " + e.getMessage());
                e.printStackTrace();
                return new ArrayList<>();
            }

            List<Map<String, Object>> ballDetections = new ArrayList<>();

            int numClasses = outputShape[1] - 4;

            try {

                for (int i = 0; i < outputShape[2]; i++) {

                    if (soccerBallClassId >= 0 && soccerBallClassId < numClasses) {
                        float score = output[0][soccerBallClassId + 4][i];

                        if (score > ballThreshold) {

                            float x = output[0][0][i];
                            float y = output[0][1][i];
                            float w = output[0][2][i];
                            float h = output[0][3][i];

                            float x1 = x - w / 2;
                            float y1 = y - h / 2;
                            float x2 = x + w / 2;
                            float y2 = y + h / 2;

                            if (isFrontCamera) {
                                float temp = 1.0f - x1;
                                x1 = 1.0f - x2;
                                x2 = temp;
                            }

                            x1 = Math.max(0, Math.min(1, x1));
                            y1 = Math.max(0, Math.min(1, y1));
                            x2 = Math.max(0, Math.min(1, x2));
                            y2 = Math.max(0, Math.min(1, y2));

                            Map<String, Object> detection = new HashMap<>();
                            detection.put("tag", "soccer_ball");
                            detection.put("confidence", score);
                            detection.put("box", new float[] { x1, y1, x2, y2 });

                            Log.d(TAG, String.format(Locale.US,
                                    "⚽ Ball erkannt: Konfidenz=%.2f, Box=[%.2f, %.2f, %.2f, %.2f]",
                                    score, x1, y1, x2, y2));

                            ballDetections.add(detection);

                            break;
                        }
                    }
                }
            } catch (Exception e) {
                Log.e(TAG, "Fehler bei der Verarbeitung der Detektionen: " + e.getMessage());
                e.printStackTrace();
            }

            return ballDetections;

        } catch (Exception e) {
            Log.e(TAG, "Fehler bei YOLOv8-Inferenz", e);
            e.printStackTrace();
            return new ArrayList<>();
        }
    }

    public void dispose() {
        try {
            if (yoloInterpreter != null) {
                yoloInterpreter.close();
                yoloInterpreter = null;
            }

            if (gpuDelegate != null) {
                gpuDelegate.close();
                gpuDelegate = null;
            }

            Log.d(TAG, "BallDetectionHelper erfolgreich freigegeben");
        } catch (Exception e) {
            Log.e(TAG, "Fehler beim Freigeben von Ressourcen", e);
        }
    }

    private Bitmap yuvPlanesToBitmap(byte[] yPlane, byte[] uPlane, byte[] vPlane,
            int width, int height, int uvRowStride, int uvPixelStride) {
        try {

            int[] argb = new int[width * height];

            for (int y = 0; y < height; y++) {
                int yRowOffset = y * width;
                int uvRowIndex = (y >> 1);
                int uvRowOffset = uvRowIndex * uvRowStride;

                for (int x = 0; x < width; x++) {
                    int yIndex = yRowOffset + x;
                    int yValue = yPlane[yIndex] & 0xFF;

                    int uvColIndex = x >> 1;
                    int uIndex = uvRowOffset + (uvColIndex * uvPixelStride);
                    int vIndex = uvRowOffset + (uvColIndex * uvPixelStride);

                    if (uIndex >= uPlane.length || vIndex >= vPlane.length) {
                        uIndex = Math.min(uIndex, uPlane.length - 1);
                        vIndex = Math.min(vIndex, vPlane.length - 1);
                    }

                    int uValue = (uPlane[uIndex] & 0xFF) - 128;
                    int vValue = (vPlane[vIndex] & 0xFF) - 128;

                    int y1192 = 1192 * (yValue - 16);
                    int r = (y1192 + 1634 * vValue);
                    int g = (y1192 - 833 * vValue - 400 * uValue);
                    int b = (y1192 + 2066 * uValue);

                    r = r < 0 ? 0 : (r > 262143 ? 255 : r >> 10);
                    g = g < 0 ? 0 : (g > 262143 ? 255 : g >> 10);
                    b = b < 0 ? 0 : (b > 262143 ? 255 : b >> 10);

                    argb[yIndex] = 0xff000000 | (r << 16) | (g << 8) | b;
                }
            }

            Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            bitmap.setPixels(argb, 0, width, 0, 0, width, height);
            return bitmap;
        } catch (Exception e) {
            Log.e(TAG, "Fehler bei der YUV zu Bitmap Konvertierung", e);
            return null;
        }
    }

    /**
     * (Fallback)
     */
    private Bitmap yuvToBitmap(byte[] yPlane, int width, int height) {
        try {

            Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
            int[] pixels = new int[width * height];

            for (int i = 0; i < height; i++) {
                for (int j = 0; j < width; j++) {
                    int y = yPlane[i * width + j] & 0xff;

                    pixels[i * width + j] = 0xff000000 | (y << 16) | (y << 8) | y;
                }
            }

            bitmap.setPixels(pixels, 0, width, 0, 0, width, height);
            return bitmap;
        } catch (Exception e) {
            Log.e(TAG, "Fehler bei der Erstellung der Grayscale-Bitmap", e);
            e.printStackTrace();
            return null;
        }
    }
}