package org.example;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.model.ObjectMetadata;
import com.amazonaws.services.s3.model.PutObjectRequest;
import com.amazonaws.services.s3.model.PutObjectResult;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.commons.fileupload.MultipartStream;
import org.example.utils.AppConfig;
import org.example.utils.AwsS3ClientFactory;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class ImageHandlerLegacy {
    private static final ObjectMapper MAPPER = new ObjectMapper();


    public Map<String, Object> handleRequest(Map<String, Object> event, Context context) {

        LambdaLogger logger = context.getLogger();

        try {
            // ── 1. Extract headers ────────────────────────────────────────────
            Map<String, String> headers = extractHeaders(event);
            String contentType = headers.getOrDefault("content-type", "");

            logger.log("Content-Type: " + contentType);
            logger.log("HTTP Method : " + event.get("httpMethod"));

            // ── 2. Validate it is actually a multipart request ────────────────
            if (!contentType.toLowerCase().contains("multipart/form-data")) {
                return buildResponse(415, "Expected multipart/form-data but got: " + contentType);
            }

            // ── 3. Extract boundary from Content-Type header ──────────────────
            String boundary = extractBoundary(contentType);
            if (boundary == null) {
                return buildResponse(400, "No boundary found in Content-Type header");
            }
            logger.log("Boundary: " + boundary);

            // ── 4. Decode body (API Gateway base64-encodes binary) ────────────
            String rawBody = (String) event.get("body");
            if (rawBody == null) {
                return buildResponse(400, "Request body is empty");
            }

            boolean isBase64 = Boolean.TRUE.equals(event.get("isBase64Encoded"));
            byte[] bodyBytes = isBase64
                    ? Base64.getDecoder().decode(rawBody)
                    : rawBody.getBytes(StandardCharsets.UTF_8);

            logger.log("Body size: " + bodyBytes.length + " bytes, base64=" + isBase64);

            // ── 5. Parse each multipart part ──────────────────────────────────
            Map<String, Object> parsedParts = parseMultipart(bodyBytes, boundary, logger);

            // ── 6. Pull out the file and text fields ──────────────────────────
            FilePart filePart = (FilePart) parsedParts.get("__file__");
            String username = (String) parsedParts.getOrDefault("username", "unknown");
            String description = (String) parsedParts.getOrDefault("description", "");

            if (filePart == null) {
                return buildResponse(400, "No file part found in multipart body");
            }

            logger.log("File received : " + filePart.filename);
            logger.log("File type     : " + filePart.contentType);
            logger.log("File size     : " + filePart.bytes.length + " bytes");
            logger.log("Uploaded by   : " + username);

            // ── 7. Hand off to your business logic ────────────────────────────
            String savedKey = processFile(filePart, username);

            // ── 8. Build success response ─────────────────────────────────────
            Map<String, Object> body = new HashMap<>();
            body.put("message", "File uploaded successfully");
            body.put("filename", filePart.filename);
            body.put("size", filePart.bytes.length);
            body.put("savedAs", savedKey);
            body.put("uploadedBy", username);

            return buildResponse(200, MAPPER.writeValueAsString(body));
        } catch (Exception e) {
//            throw new RuntimeException(e);
            e.printStackTrace();
        }

//        Extract Binary

//        Call S3 Client

//        Define Bucket Level Triggers On Put Request

//        Return Success ==> It will lead to Node.js Lambda that would eventually generate the thumbnail and store to s3


        return buildResponse(200,"File Received Succesfully");

    }

    // ─────────────────────────────────────────────────────────────────────────
    // Multipart parsing using Apache Commons MultipartStream
    // ─────────────────────────────────────────────────────────────────────────

    private Map<String, Object> parseMultipart(byte[] body, String boundary,
                                               LambdaLogger logger) throws IOException {

        Map<String, Object> parts = new HashMap<>();
        ByteArrayInputStream inputStream = new ByteArrayInputStream(body);

        MultipartStream multipartStream = new MultipartStream(
                inputStream,
                boundary.getBytes(StandardCharsets.UTF_8),
                4096,
                null
        );

        boolean hasNextPart = multipartStream.skipPreamble();

        while (hasNextPart) {
            // Read this part's headers (Content-Disposition, Content-Type etc.)
            String partHeaders = multipartStream.readHeaders();
            logger.log("Part headers: " + partHeaders);

            // Read this part's body bytes
            ByteArrayOutputStream partBody = new ByteArrayOutputStream();
            multipartStream.readBodyData(partBody);

            String fieldName = extractFieldName(partHeaders);
            String fileName = extractFileName(partHeaders);
            String partContentType = extractPartContentType(partHeaders);

            if (fieldName == null) {
                hasNextPart = multipartStream.readBoundary();
                continue;
            }

            if (fileName != null) {
                // It's a file part
                FilePart fp = new FilePart();
                fp.filename = fileName;
                fp.contentType = partContentType;
                fp.bytes = partBody.toByteArray();
                fp.fieldName = fieldName;
                parts.put("__file__", fp);     // use fieldName as key if you expect multiple files
            } else {
                // It's a plain text field
                parts.put(fieldName, partBody.toString(StandardCharsets.UTF_8));
            }

            hasNextPart = multipartStream.readBoundary();
        }

        return parts;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Business logic placeholder — plug in your S3 upload, DB write, etc.
    // ─────────────────────────────────────────────────────────────────────────

    private String processFile(FilePart file, String username) {
//         Example: upload to S3
        AmazonS3 client = AwsS3ClientFactory.getClient();
        String key = "uploads/" + username + "/" + file.filename;
        ObjectMetadata metadata = new ObjectMetadata();
        metadata.setContentType(file.contentType);
        metadata.setContentLength(file.bytes.length);

        PutObjectResult putObjectResult = client.putObject(new PutObjectRequest(
                AppConfig.IMAGES_BUCKET,
                key,
                new ByteArrayInputStream(file.bytes),
                metadata
        ));


        return key+putObjectResult;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Header / boundary helpers
    // ─────────────────────────────────────────────────────────────────────────

    @SuppressWarnings("unchecked")
    private Map<String, String> extractHeaders(Map<String, Object> event) {
        Object h = event.get("headers");
        if (h instanceof Map) return (Map<String, String>) h;
        return new HashMap<>();
    }

    private String extractBoundary(String contentType) {
        for (String token : contentType.split(";")) {
            token = token.trim();
            if (token.startsWith("boundary=")) {
                return token.substring("boundary=".length()).replace("\"", "");
            }
        }
        return null;
    }

    private String extractFieldName(String headers) {
        Matcher m = Pattern.compile("name=\"([^\"]+)\"").matcher(headers);
        return m.find() ? m.group(1) : null;
    }

    private String extractFileName(String headers) {
        Matcher m = Pattern.compile("filename=\"([^\"]+)\"").matcher(headers);
        return m.find() ? m.group(1) : null;
    }

    private String extractPartContentType(String headers) {
        Matcher m = Pattern.compile("(?i)Content-Type:\\s*([^\\r\\n]+)").matcher(headers);
        return m.find() ? m.group(1).trim() : "application/octet-stream";
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Response builder — API Gateway expects this exact shape
    // ─────────────────────────────────────────────────────────────────────────

    private Map<String, Object> buildResponse(int statusCode, String body) {
        Map<String, Object> response = new HashMap<>();
        Map<String, String> responseHeaders = new HashMap<>();

        responseHeaders.put("Content-Type", "application/json");
        responseHeaders.put("Access-Control-Allow-Origin", "*");

        response.put("statusCode", statusCode);
        response.put("headers", responseHeaders);
        response.put("body", body);
        return response;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Inner class — holds one parsed file part (analogous to MultipartFile)
    // ─────────────────────────────────────────────────────────────────────────

    public static class FilePart {
        public String fieldName;    // the HTML input name="..."
        public String filename;     // original file name from client
        public String contentType;  // image/jpeg, application/pdf etc.
        public byte[] bytes;        // raw file bytes

        // Convenience — analogous to MultipartFile.getInputStream()
        public InputStream getInputStream() {
            return new ByteArrayInputStream(bytes);
        }

        // Convenience — analogous to MultipartFile.getSize()
        public long getSize() {
            return bytes.length;
        }

    }
}
