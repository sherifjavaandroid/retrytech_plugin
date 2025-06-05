/*
 * Copyright 2022 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.retrytech.retrytech_plugin.filter;

import static androidx.media3.common.util.Assertions.checkState;

import android.content.Context;

import androidx.media3.common.VideoFrameProcessingException;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.effect.BaseGlShaderProgram;
import androidx.media3.effect.DefaultVideoFrameProcessor;
import androidx.media3.effect.RgbMatrix;

import java.util.Arrays;
import java.util.List;
import java.util.Objects;


/**
 * Provides common color filters.
 *
 * <p>This effect assumes a {@linkplain DefaultVideoFrameProcessor#WORKING_COLOR_SPACE_LINEAR
 * linear} working color space.
 */
@UnstableApi
public final class RgbFilter implements RgbMatrix {
    private static final int COLOR_FILTER_GRAYSCALE_INDEX = 1;
    private static final int COLOR_FILTER_INVERTED_INDEX = 2;
    private static final int COLOR_FILTER_SEPIA_INDEX = 3;

    // Grayscale transformation matrix using the BT.709 luminance coefficients from
    // https://en.wikipedia.org/wiki/Grayscale#Converting_colour_to_grayscale
    private static final float[] FILTER_MATRIX_GRAYSCALE_SDR = {
            0.2126f, 0.2126f, 0.2126f, 0, 0.7152f, 0.7152f, 0.7152f, 0, 0.0722f, 0.0722f, 0.0722f, 0, 0, 0,
            0, 1
    };
    private static final float[] FILTER_MATRIX_SEPIA = {
            0.393f, 0.349f, 0.272f, 0,
            0.769f, 0.686f, 0.534f, 0,
            0.189f, 0.168f, 0.131f, 0,
            0f, 0f, 0f, 1f
    };
    private static final float[] FILTER_MATRIX_INVERT = {
            -1f, 0f, 0f, 0f,
            0f, -1f, 0f, 0f,
            0f, 0f, -1f, 0f,
            1f, 1f, 1f, 1f  // Offset to bring values back into visible range
    };
    private static final float[] FILTER_MATRIX_BRIGHTNESS = {
            1f, 0f, 0f, 0f,
            0f, 1f, 0f, 0f,
            0f, 0f, 1f, 0f,
            0.1f, 0.1f, 0.1f, 1f // Adds brightness
    };
    private static final float[] FILTER_MATRIX_CONTRAST = {
            1.5f, 0f, 0f, 0f,
            0f, 1.5f, 0f, 0f,
            0f, 0f, 1.5f, 0f,
            -0.25f, -0.25f, -0.25f, 1f  // Adjust offset for contrast correction
    };
    private static final float[] FILTER_MATRIX_COOL = {
            0.8f, 0f, 0f, 0f, 0f,
            0f, 0.8f, 0.1f, 0f, 0f,
            0.1f, 0.1f, 1.2f, 0f, 0f,
            0f, 0f, 0f, 1f, 0f
    };

    List<Filter> filters = Arrays.asList(
            new Filter("Normal", new float[]{
                    1f, 0f, 0f, 0f, 0f,
                    0f, 1f, 0f, 0f, 0f,
                    0f, 0f, 1f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Vintage", new float[]{
                    1.0f, 0.2f, 0f, 0f, 0f,
                    0.2f, 1.0f, 0.2f, 0f, 0f,
                    0f, 0.2f, 1.0f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Warm", new float[]{
                    1.2f, 0.1f, 0f, 0f, 0f,
                    0.1f, 1.1f, 0.1f, 0f, 0f,
                    0f, 0.1f, 1.0f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Cool", new float[]{
                    0.8f, 0f, 0f, 0f, 0f,
                    0f, 0.8f, 0.1f, 0f, 0f,
                    0.1f, 0.1f, 1.2f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Grayscale", new float[]{
                    0.33f, 0.33f, 0.33f, 0f, 0f,
                    0.33f, 0.33f, 0.33f, 0f, 0f,
                    0.33f, 0.33f, 0.33f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Low Saturation", new float[]{
                    0.5f, 0.25f, 0.25f, 0f, 0f,
                    0.25f, 0.5f, 0.25f, 0f, 0f,
                    0.25f, 0.25f, 0.5f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Night Vision", new float[]{
                    0.1f, 0.4f, 0f, 0f, 0f,
                    0.3f, 1.0f, 0.3f, 0f, 0f,
                    0f, 0.4f, 0.1f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),
            new Filter("Vintage Purple", new float[]{
                    0.6f, 0.2f, 0.8f, 0f, 0f,
                    0.3f, 0.3f, 0.5f, 0f, 0f,
                    0.3f, 0.1f, 0.6f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Cool Tone", new float[]{
                    0.9f, 0.1f, 0f, 0f, 0f,
                    0.1f, 0.9f, 0.1f, 0f, 0f,
                    0f, 0.1f, 1.1f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Warm Tone", new float[]{
                    1.2f, 0.2f, 0.1f, 0f, 0f,
                    0.2f, 1.1f, 0.1f, 0f, 0f,
                    0.1f, 0.1f, 0.9f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Shadow Boost", new float[]{
                    1f, 0f, 0f, 0f, -50f,
                    0f, 1f, 0f, 0f, -50f,
                    0f, 0f, 1f, 0f, -50f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Faded", new float[]{
                    1f, 0.2f, 0.2f, 0f, -30f,
                    0.2f, 1f, 0.2f, 0f, -30f,
                    0.2f, 0.2f, 1f, 0f, -30f,
                    0f, 0f, 0f, 1f, 0f
            }),

            new Filter("Green Boost", new float[]{
                    1f, 0.1f, 0f, 0f, 0f,
                    0.1f, 1.5f, 0.1f, 0f, 0f,
                    0f, 0.1f, 1f, 0f, 0f,
                    0f, 0f, 0f, 1f, 0f
            })
    );


    // Grayscale transformation using the BT.2020 primary colors from
    // https://www.itu.int/dms_pubrec/itu-r/rec/bt/R-REC-BT.2020-2-201510-I!!PDF-E.pdf
    // TODO(b/241240659): Add HDR tests once infrastructure supports it.
    private static final float[] FILTER_MATRIX_GRAYSCALE_HDR = {
            0.2627f, 0.2627f, 0.2627f, 0, 0.6780f, 0.6780f, 0.6780f, 0, 0.0593f, 0.0593f, 0.0593f, 0, 0, 0,
            0, 1
    };
    // Inverted filter uses the transformation R' = -R + 1 = 1 - R.
    private static final float[] FILTER_MATRIX_INVERTED = {
            -1, 0, 0, 0, 0, -1, 0, 0, 0, 0, -1, 0, 1, 1, 1, 1
    };

    private int colorFilter;
    private String colorFilterName;
    private float[] colorFilterValues;

    /**
     * Ensures that the usage of HDR is consistent. {@code null} indicates that HDR has not yet been
     * set.
     */
    private Boolean useHdr;

    /**
     * Creates a new grayscale {@code RgbFilter} instance.
     */
    public static RgbFilter createGrayscaleFilter() {
        return new RgbFilter(COLOR_FILTER_GRAYSCALE_INDEX);
    }

    /**
     * Creates a new inverted {@code RgbFilter} instance.
     */
    public static RgbFilter createInvertedFilter() {
        return new RgbFilter(COLOR_FILTER_INVERTED_INDEX);
    }

    public static RgbFilter createSepiaFilter() {
        return new RgbFilter(COLOR_FILTER_SEPIA_INDEX);
    }

    public RgbFilter(int colorFilter) {
        this.colorFilter = colorFilter;
    }

    public RgbFilter(String colorFilter) {
        this.colorFilterName = colorFilter;
    }

    public RgbFilter(float[] colorFilter) {
        this.colorFilterValues = colorFilter;
    }

    private void checkForConsistentHdrSetting(boolean useHdr) {
        if (this.useHdr == null) {
            this.useHdr = useHdr;
        } else {
            checkState(this.useHdr == useHdr, "Changing HDR setting is not supported.");
        }
    }

    @Override
    public float[] getMatrix(long presentationTimeUs, boolean useHdr) {
        checkForConsistentHdrSetting(useHdr);
        return extractColorChannelMixerParams(colorFilterValues);
//        switch (colorFilterName) {
//            case "Normal":
//                return filters.get(0).getColorWith4Line();
//            case "Vintage":
//                return filters.get(1).getColorWith4Line();
//            case "Warm":
//                return filters.get(2).getColorWith4Line();
//            case "Cool":
//                return filters.get(3).getColorWith4Line();
//            case "Grayscale":
//                return filters.get(4).getColorWith4Line();
//            case "Low Saturation":
//                return filters.get(5).getColorWith4Line();
//            case "Night Vision":
//                return filters.get(6).getColorWith4Line();
////            case "Vintage Purple":
////                return filters.get(7).getColorWith4Line();
//            case "Cool Tone":
//                return filters.get(8).getColorWith4Line();
//            case "Warm Tone":
//                return filters.get(9).getColorWith4Line();
////            case "Shadow Boost":
////                return filters.get(10).getColorWith4Line();
//            case "Faded":
//                return filters.get(11).getColorWith4Line();
//            case "Green Boost":
//                return filters.get(12).getColorWith4Line();
//            default:
//                // Should never happen.
//                throw new IllegalStateException("Invalid color filter " + colorFilter);
//        }
//        throw new IllegalStateException("Invalid color filter " + colorFilter);
    }

    @Override
    public BaseGlShaderProgram toGlShaderProgram(Context context, boolean useHdr)
            throws VideoFrameProcessingException {
        checkForConsistentHdrSetting(useHdr);
        return RgbMatrix.super.toGlShaderProgram(context, useHdr);
    }

    public class Filter {
        private final String filterName;
        private final float[] colorFilter;

        public Filter(String filterName, float[] colorFilter) {
            this.filterName = filterName;
            this.colorFilter = colorFilter;
        }

        public String getFilterName() {
            return filterName;
        }

        public float[] getColorFilter() {
            return colorFilter;
        }

        public float[] getColorWith4Line() {
            return extractColorChannelMixerParams(colorFilter);
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (!(o instanceof Filter)) return false;
            Filter filter = (Filter) o;
            return Objects.equals(filterName, filter.filterName) &&
                    Arrays.equals(colorFilter, filter.colorFilter);
        }

        @Override
        public int hashCode() {
            int result = Objects.hash(filterName);
            result = 31 * result + Arrays.hashCode(colorFilter);
            return result;
        }


    }

    public float[] extractColorChannelMixerParams(float[] matrix) {
        if (matrix.length != 20) {
            throw new IllegalArgumentException("Matrix must have exactly 20 elements.");
        }

        float rr = matrix[0];
        float rg = matrix[1];
        float rb = matrix[2];
        float ra = matrix[3];
        float gr = matrix[5];
        float gg = matrix[6];
        float gb = matrix[7];
        float ga = matrix[8];
        float br = matrix[10];
        float bg = matrix[11];
        float bb = matrix[12];
        float ba = matrix[13];
        float ar = matrix[15];
        float ag = matrix[16];
        float ab = matrix[17];
        float aa = matrix[18];

        return new float[]{
                rr, rg, rb, ra,
                gr, gg, gb, ga,
                br, bg, bb, ba,
                ar, ag, ab, aa
        };
    }
}


