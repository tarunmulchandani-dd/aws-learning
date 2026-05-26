package org.example.utils;
public class AppConfig {

    // Buckets — injected by CloudFormation via !Ref
    public static final String IMAGES_BUCKET     = requireEnv("IMAGES_BUCKET");
    public static final String THUMBNAILS_BUCKET = requireEnv("THUMBNAILS_BUCKET");

    // Stage
    public static final String STAGE   = requireEnv("STAGE");
    public static final String REGION  = System.getenv().getOrDefault("AWS_REGION", "us-east-1");

    // Floci / LocalStack — only set locally
    public static final String S3_ENDPOINT = System.getenv("S3_ENDPOINT_URL");

    public static boolean isLocal() {
        return S3_ENDPOINT != null && !S3_ENDPOINT.isBlank();
    }

    private static String requireEnv(String key) {
        String value = System.getenv(key);
        if (value == null || value.isBlank()) {
//            throw new IllegalStateException("Missing required env var: " + key);
            return "";
        }
        return value;
    }
}