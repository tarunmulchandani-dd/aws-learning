package org.example;

import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyRequestEvent;
import com.amazonaws.services.lambda.runtime.events.APIGatewayProxyResponseEvent;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.model.GeneratePresignedUrlRequest;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.example.utils.AwsS3ClientFactory;

import java.net.URL;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;
import java.util.logging.Level;
import java.util.logging.LogRecord;
import java.util.logging.Logger;

public class ImageUrlGenerator implements RequestHandler<APIGatewayProxyRequestEvent, APIGatewayProxyResponseEvent> {

    private static final Logger logger = Logger.getLogger(ImageUrlGenerator.class.getName());
    private static final int EXPIRY_MINUTES = 10;
    private static final ObjectMapper MAPPER = new ObjectMapper();

//    public Map<String,String> handleRequest(Map<String,String> imageUploadRequest,Context context){
//
//        return null;
//    }

    @Override
    public APIGatewayProxyResponseEvent handleRequest(APIGatewayProxyRequestEvent input, Context context) {
//        Generate the Presigned request valid for the 5 minutes.

        Map<String, String> queryStringParameters = input.getQueryStringParameters();


        String filename = queryStringParameters.get("filename");
        String username = queryStringParameters.get("username");
        String contentType = queryStringParameters.getOrDefault("contentType", "image/jpeg");

        logger.log(Level.INFO, "Generating presigned URL for file: " + filename + " by: " + username);

        // ── 2. Build S3 key ──────────────────────────────────────────────
        String bucket = System.getenv("IMAGES_BUCKET");
        String key    = "uploads/" + username + "/" + filename;

        // ── 3. Build S3 Client ───────────────────────────────────────────
        AmazonS3 s3Client = AwsS3ClientFactory.getClient();

        // ── 4. Generate Presigned URL ────────────────────────────────────
        Date expiry = new Date(System.currentTimeMillis() + (EXPIRY_MINUTES * 60 * 1000L));

        GeneratePresignedUrlRequest presignedUrlRequest =
                new GeneratePresignedUrlRequest(bucket, key)
                        .withMethod(com.amazonaws.HttpMethod.PUT)
                        .withContentType(contentType)
                        .withExpiration(expiry);

        URL presignedUrl = s3Client.generatePresignedUrl(presignedUrlRequest);

        logger.log( Level.INFO,"Presigned URL generated: " + presignedUrl.toString());

        // ── 5. Build response body ───────────────────────────────────────
        Map<String, Object> responseBody = new HashMap<>();
        responseBody.put("uploadUrl",  presignedUrl.toString());
        responseBody.put("key",        key);
        responseBody.put("bucket",     bucket);
        responseBody.put("expiresIn",  EXPIRY_MINUTES + " minutes");
        responseBody.put("filename",   filename);
        responseBody.put("uploadedBy", username);

        try {
            return buildResponse(200, MAPPER.writeValueAsString(responseBody));
        } catch (JsonProcessingException e) {
//            throw new RuntimeException(e);
            e.printStackTrace();
            return buildResponse(400, e.getMessage());
        }


//        Return to the client

//        return null;
    }

    private APIGatewayProxyResponseEvent buildResponse(int statusCode, String body) {
        Map<String, String> headers = new HashMap<>();
        headers.put("Content-Type", "application/json");
        headers.put("Access-Control-Allow-Origin", "*");

        return new APIGatewayProxyResponseEvent()
                .withStatusCode(statusCode)
                .withHeaders(headers)
                .withBody(body);
    }
}
