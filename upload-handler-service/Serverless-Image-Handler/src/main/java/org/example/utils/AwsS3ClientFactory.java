package org.example.utils;

import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.amazonaws.client.builder.AwsClientBuilder;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;

public class AwsS3ClientFactory {

    private static AmazonS3 s3Client;

    public static AmazonS3 getClient() {
        if (s3Client != null) return s3Client;

        String endpoint = System.getenv().getOrDefault("S3_ENDPOINT_URL","http://host.docker.internal:4566/");
        String region   = System.getenv().getOrDefault("AWS_REGION", "us-east-1");

        if (endpoint != null && !endpoint.isBlank()) {
            // Local — Floci
            s3Client = AmazonS3ClientBuilder.standard()
                    .withEndpointConfiguration(new AwsClientBuilder.EndpointConfiguration(endpoint, region))
                    .withCredentials(new AWSStaticCredentialsProvider(
                            new BasicAWSCredentials("test", "test")
                    ))
                    .withPathStyleAccessEnabled(true)
                    .build();
        } else {
            // Production — Lambda IAM role handles auth
            s3Client = AmazonS3ClientBuilder.standard()
                    .withRegion(region)
                    .build();
        }

        return s3Client;
    }
}