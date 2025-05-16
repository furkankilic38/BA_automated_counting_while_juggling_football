/**
 * Autor: Furkan Kilic
 * 
 * Diese Datei implementiert die Pose-Erkennung mit dem MoveNet-Modell für die Footballista-App.
 * Stellt eine Schnittstelle zwischen dem Flutter-Framework und den nativen TensorFlow Lite-Funktionen 
 * für die Körperhaltungserkennung bereit.
 */

package com.example.footy_testing.pose;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Matrix;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.YuvImage;
import android.graphics.ImageFormat;
import android.util.Log;

import androidx.annotation.NonNull;

import org.tensorflow.lite.Interpreter;
import org.tensorflow.lite.gpu.GpuDelegate;
import org.tensorflow.lite.support.common.FileUtil;

import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.*;
import java.util.Locale;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;


public class MoveNetHelper implements MethodChannel.MethodCallHandler {
    private static final String TAG = "MoveNetHelper";
    private static final String CHANNEL = "com.example.footy_testing/detection";

    private static final int INPUT_SIZE = 192;

    private static final String[] KEYPOINT_NAMES = {
            "nose", "left_eye", "right_eye", "left_ear", "right_ear",
            "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
            "left_wrist", "right_wrist", "left_hip", "right_hip",
            "left_knee", "right_knee", "left_ankle", "right_ankle"
    };

    private final Context context;
    private Interpreter moveNetInterpreter;
    private GpuDelegate gpuDelegate;

   
    public static void registerWith(FlutterEngine flutterEngine, Context context) {
        MethodChannel channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        MoveNetHelper helper = new MoveNetHelper(context);
        channel.setMethodCallHandler(helper);
    }

    public MoveNetHelper(Context context) {
        this.context = context;
    }

    
    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "loadModels":
                try {
                    Map<String, Object> args = call.arguments();
                    String modelPath = ((String) args.get("movenetModelPath"));
                    boolean useGpu = args.containsKey("useGpu") ? (boolean) args.get("useGpu") : false;

                    if (modelPath == null) {
                        Log.e(TAG, "Model path is null! Arguments: " + args.toString());
                        result.error("NULL_MODEL_PATH", "MoveNet model path cannot be null", null);
                        return;
                    }

                    if (modelPath.startsWith("assets/"))
                        modelPath = modelPath.substring(7);

                    Log.d(TAG, "Lade MoveNet-Modell: " + modelPath);

                    Interpreter.Options options = new Interpreter.Options();
                    options.setNumThreads(4);

                    try {
                        options.setUseNNAPI(true);
                        Log.d(TAG, "NNAPI für MoveNet aktiviert");
                    } catch (Exception e) {
                        Log.w(TAG, "NNAPI konnte nicht aktiviert werden: " + e.getMessage());
                    }

                    if (useGpu) {
                        try {
                            gpuDelegate = new GpuDelegate();
                            options.addDelegate(gpuDelegate);

                            options.setUseNNAPI(false);
                            Log.d(TAG, "GPU-Delegate aktiviert für MoveNet");
                        } catch (Exception e) {
                            Log.w(TAG, "GPU-Delegate nicht verfügbar, verwende CPU: " + e.getMessage());

                            try {
                                options.setUseNNAPI(true);
                                Log.d(TAG, "Fallback auf NNAPI");
                            } catch (Exception nnError) {
                                Log.w(TAG, "NNAPI auch nicht verfügbar: " + nnError.getMessage());
                            }
                        }
                    }

                    moveNetInterpreter = new Interpreter(FileUtil.loadMappedFile(context, modelPath), options);

                    int[] inputShape = moveNetInterpreter.getInputTensor(0).shape();
                    int[] outputShape = moveNetInterpreter.getOutputTensor(0).shape();

                    String inputShapeStr = Arrays.toString(inputShape);
                    String outputShapeStr = Arrays.toString(outputShape);

                    Log.d(TAG, "Modell geladen - Eingabeform: " + inputShapeStr);
                    Log.d(TAG, "Modell geladen - Ausgabeform: " + outputShapeStr);

                    int inputBytes = 1;
                    for (int dim : inputShape) {
                        inputBytes *= dim;
                    }
                    inputBytes *= 4;

                    Log.d(TAG, "Erwartete Input-Bytegröße: " + inputBytes);

                    Log.d(TAG, "Input-Tensor Datentyp: " + moveNetInterpreter.getInputTensor(0).dataType());
                    Log.d(TAG, "Output-Tensor Datentyp: " + moveNetInterpreter.getOutputTensor(0).dataType());

                    result.success(true);
                } catch (Exception e) {
                    Log.e(TAG, "Fehler beim Laden des Modells", e);
                    e.printStackTrace();
                    result.error("LOAD_FAIL", e.getMessage(), null);
                }
                break;

            case "detectObjects":
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
                            "Pose-Erkennung, Bildgröße: " + width + "x" + height + ", Frontkamera: " + isFrontCamera);

                    long startTime = System.currentTimeMillis();

                    Bitmap bitmap;
                    if (uPlane != null && vPlane != null) {
                        bitmap = yuvPlanesToBitmap(yPlane, uPlane, vPlane, width, height, uvRowStride, uvPixelStride);
                    } else {
                        bitmap = yuvToBitmap(yPlane, width, height);
                    }

                    if (bitmap == null) {
                        Log.e(TAG, "Fehler bei der Bildkonvertierung");
                        Map<String, Object> resultMap = new HashMap<>();
                        resultMap.put("detections", new ArrayList<>());
                        resultMap.put("processingTimeMs", System.currentTimeMillis() - startTime);
                        resultMap.put("error", "Fehler bei der Bildkonvertierung");
                        result.success(resultMap);
                        return;
                    }

                    Map<String, Object> poseResult = detectPose(bitmap, rotation, isFrontCamera);

                    List<Map<String, Object>> detections = new ArrayList<>();
                    if (poseResult.containsKey("detections")) {
                        detections = (List<Map<String, Object>>) poseResult.get("detections");
                    }

                    long inferenceTime = 0;
                    if (poseResult.containsKey("inferenceTime")) {
                        Object timeValue = poseResult.get("inferenceTime");
                        if (timeValue instanceof Long) {
                            inferenceTime = (long) timeValue;
                        } else if (timeValue instanceof Integer) {
                            inferenceTime = ((Integer) timeValue).longValue();
                        }
                    }

                    bitmap.recycle();

                    long totalTime = System.currentTimeMillis() - startTime;

                    Map<String, Object> resultMap = new HashMap<>();
                    resultMap.put("detections", detections);
                    resultMap.put("processingTimeMs", totalTime);
                    resultMap.put("inferenceTimeMs", inferenceTime);

                    Log.d(TAG, "Pose-Erkennung abgeschlossen in " + totalTime + "ms, Inferenz: " +
                            inferenceTime + "ms, gefunden: " + detections.size() + " Personen");

                    result.success(resultMap);
                } catch (Exception e) {
                    Log.e(TAG, "Fehler bei der Pose-Erkennung", e);
                    e.printStackTrace();

                    Map<String, Object> errorResult = new HashMap<>();
                    errorResult.put("detections", new ArrayList<>());
                    errorResult.put("processingTimeMs", 0);
                    errorResult.put("error", e.getMessage());
                    result.success(errorResult);
                }
                break;

            case "dispose":
                dispose();
                result.success(true);
                break;

            default:
                result.notImplemented();
        }
    }

    private Map<String, Object> detectPose(Bitmap bitmap, int rotation) {
        return detectPose(bitmap, rotation, false);
    }

    /**
     * Erkennt Posen im Bild mit dem MoveNet-Modell
     * 
     * @param bitmap        Das zu analysierende Bild
     * @param rotation      Rotation des Bildes in Grad
     * @param isFrontCamera Gibt an, ob das Bild von der Frontkamera stammt
     * @return Map mit erkannten Personen und Keypoints
     */
    private Map<String, Object> detectPose(Bitmap bitmap, int rotation, boolean isFrontCamera) {
        if (moveNetInterpreter == null) {
            Log.e(TAG, "MoveNet Interpreter ist null");
            return new HashMap<>();
        }

        try {

            int modelWidth = 192;
            int modelHeight = 192;

            Log.d(TAG, "Verarbeite Bild mit Rotation: " + rotation + " Grad, Frontkamera: " + isFrontCamera);

            long preprocessStart = System.currentTimeMillis();

            Bitmap scaledBitmap;

            if (rotation == 90 || rotation == 270) {

                Matrix rotationMatrix = new Matrix();
                rotationMatrix.postRotate(rotation);

                try {
                    Bitmap rotatedBitmap = Bitmap.createBitmap(
                            bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(),
                            rotationMatrix, true);

                    scaledBitmap = Bitmap.createScaledBitmap(
                            rotatedBitmap, modelWidth, modelHeight, false);

                    if (rotatedBitmap != bitmap) {
                        rotatedBitmap.recycle();
                    }
                } catch (OutOfMemoryError e) {
                    Log.w(TAG, "Speicherproblem bei der Bildverarbeitung: " + e.getMessage());

                    scaledBitmap = Bitmap.createScaledBitmap(bitmap, modelWidth, modelHeight, false);
                }
            } else if (bitmap.getWidth() == modelWidth && bitmap.getHeight() == modelHeight && rotation == 0) {

                scaledBitmap = bitmap;
            } else if (rotation != 0) {

                Matrix rotationMatrix = new Matrix();
                rotationMatrix.postRotate(rotation);
                rotationMatrix.postScale((float) modelWidth / bitmap.getWidth(),
                        (float) modelHeight / bitmap.getHeight());

                try {
                    scaledBitmap = Bitmap.createBitmap(
                            bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(),
                            rotationMatrix, true);
                } catch (OutOfMemoryError e) {

                    Log.w(TAG, "Speicheroptimierte Bildverarbeitung wegen OOM");
                    Matrix onlyRotation = new Matrix();
                    onlyRotation.postRotate(rotation);
                    Bitmap rotatedBitmap = Bitmap.createBitmap(
                            bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(),
                            onlyRotation, true);
                    scaledBitmap = Bitmap.createScaledBitmap(rotatedBitmap, modelWidth, modelHeight, false);
                    rotatedBitmap.recycle();
                }
            } else {

                scaledBitmap = Bitmap.createScaledBitmap(bitmap, modelWidth, modelHeight, false);
            }

            long preprocessEnd = System.currentTimeMillis();
            Log.d(TAG, "Bildvorverarbeitung: " + (preprocessEnd - preprocessStart) + "ms");

            int[] inputShape = moveNetInterpreter.getInputTensor(0).shape();
            Log.d(TAG, "Eingangsform des Modells: " + Arrays.toString(inputShape));

            int batchSize = inputShape[0];
            int inputHeight = inputShape[1];
            int inputWidth = inputShape[2];
            int channels = inputShape[3];

            int bufferSizeNeeded = batchSize * inputHeight * inputWidth * channels;

            int bytesPerChannel = 1;
            int bufferSize = bufferSizeNeeded * bytesPerChannel;
            Log.d(TAG, "Korrigierte BufferGröße: " + bufferSize + " Bytes");

            ByteBuffer imgData = ByteBuffer.allocateDirect(bufferSize);
            imgData.order(ByteOrder.nativeOrder());

            int[] pixels = new int[inputWidth * inputHeight];
            scaledBitmap.getPixels(pixels, 0, inputWidth, 0, 0, inputWidth, inputHeight);

            int pixel = 0;

            for (int i = 0; i < inputHeight; i++) {
                for (int j = 0; j < inputWidth; j++) {
                    int pixelValue = pixels[pixel++];

                    int r = (pixelValue >> 16) & 0xFF;
                    int g = (pixelValue >> 8) & 0xFF;
                    int b = pixelValue & 0xFF;

                    imgData.put((byte) r);
                    imgData.put((byte) g);
                    imgData.put((byte) b);
                }
            }

            Log.d(TAG, "ByteBuffer position after filling: " + imgData.position() + " capacity: " + imgData.capacity());

            scaledBitmap.recycle();

            imgData.rewind();

            float[][][][] outputTensor = new float[1][1][17][3];

            long inferenceStartTime = System.currentTimeMillis();

            try {
                moveNetInterpreter.run(imgData, outputTensor);
                Log.d(TAG, "MoveNet-Inferenz erfolgreich durchgeführt");
            } catch (Exception e) {
                Log.e(TAG, "Fehler bei der MoveNet-Inferenz: " + e.getMessage());

                if (e.getMessage() != null && e.getMessage().contains("Cannot copy to a TensorFlowLite tensor")) {
                    Log.d(TAG, "Versuche alternative Eingabeverarbeitung...");

                    ByteBuffer imgDataFloat = ByteBuffer.allocateDirect(inputWidth * inputHeight * channels * 4);
                    imgDataFloat.order(ByteOrder.nativeOrder());

                    pixel = 0;

                    for (int i = 0; i < inputHeight; i++) {
                        for (int j = 0; j < inputWidth; j++) {
                            int pixelValue = pixels[pixel++];

                            float r = ((pixelValue >> 16) & 0xFF) / 255.0f;
                            float g = ((pixelValue >> 8) & 0xFF) / 255.0f;
                            float b = (pixelValue & 0xFF) / 255.0f;

                            imgDataFloat.putFloat(r);
                            imgDataFloat.putFloat(g);
                            imgDataFloat.putFloat(b);
                        }
                    }

                    imgDataFloat.rewind();
                    moveNetInterpreter.run(imgDataFloat, outputTensor);
                    Log.d(TAG, "Alternative MoveNet-Inferenz erfolgreich durchgeführt");
                } else {
                    throw e;
                }
            }

            long inferenceTime = System.currentTimeMillis() - inferenceStartTime;

            List<Map<String, Object>> personDetections = new ArrayList<>();
            float[][][] personData = outputTensor[0];

            Map<String, Object> personDetection = new HashMap<>();
            personDetection.put("tag", "person");
            personDetection.put("confidence", 1.0f);

            List<Map<String, Object>> keypointsList = new ArrayList<>();
            float minX = 1.0f, minY = 1.0f, maxX = 0.0f, maxY = 0.0f;
            boolean hasValidKeypoints = false;

            float minScoreThresh = 0.2f;

            for (int i = 0; i < 17; i++) {
                float y = personData[0][i][0];
                float x = personData[0][i][1];

                if (isFrontCamera) {
                    x = 1.0f - x;
                }

                float score = personData[0][i][2];

                Map<String, Object> keypoint = new HashMap<>();
                keypoint.put("name", KEYPOINT_NAMES[i]);
                keypoint.put("x", x);
                keypoint.put("y", y);
                keypoint.put("score", score);

                keypointsList.add(keypoint);

                Log.d(TAG, "Keypoint " + KEYPOINT_NAMES[i] + ": x=" + x + ", y=" + y + ", score=" + score);

                if (score > minScoreThresh) {
                    minX = Math.min(minX, x);
                    minY = Math.min(minY, y);
                    maxX = Math.max(maxX, x);
                    maxY = Math.max(maxY, y);
                    hasValidKeypoints = true;
                }
            }

            personDetection.put("keypoints", keypointsList);

            if (hasValidKeypoints) {

                float boxBuffer = 0.05f;
                minX = Math.max(0.0f, minX - boxBuffer);
                minY = Math.max(0.0f, minY - boxBuffer);
                maxX = Math.min(1.0f, maxX + boxBuffer);
                maxY = Math.min(1.0f, maxY + boxBuffer);

                List<Float> box = Arrays.asList(minX, minY, maxX, maxY);
                personDetection.put("box", box);
                personDetections.add(personDetection);

                Log.d(TAG, "Person-Box: [" + minX + ", " + minY + ", " + maxX + ", " + maxY + "]");
                Log.d(TAG, "Anzahl Keypoints mit Konfidenz > " + minScoreThresh + ": " + keypointsList.size());
            }

            Map<String, Object> result = new HashMap<>();
            result.put("detections", personDetections);
            result.put("inferenceTime", inferenceTime);

            return result;
        } catch (Exception e) {
            Log.e(TAG, "Fehler bei der Pose-Erkennung", e);
            e.printStackTrace();
            return new HashMap<>();
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
            Log.e(TAG, "Fehler bei YUV zu Bitmap Konvertierung", e);
            e.printStackTrace();
            return yuvToBitmap(yPlane, width, height);
        }
    }

   
    private void dispose() {
        if (moveNetInterpreter != null) {
            moveNetInterpreter.close();
            moveNetInterpreter = null;
        }
        if (gpuDelegate != null) {
            gpuDelegate.close();
            gpuDelegate = null;
        }
    }
}