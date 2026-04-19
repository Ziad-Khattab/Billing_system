package com.billing;

import com.billing.cdr.CDRParser;

public class TestMain {
    public static void main(String[] args) {

        String sourceDir = "input";
        String destDir = "processed";

        System.out.println("Starting CDR ingestion pipeline...");

        CDRParser.processAll(sourceDir, destDir);

        System.out.println("Pipeline finished.");
    }
}