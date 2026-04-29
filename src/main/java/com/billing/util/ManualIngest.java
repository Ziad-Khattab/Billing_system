package com.billing.util;

import com.billing.cdr.CDRParser;
import java.io.File;

public class ManualIngest {
    public static void main(String[] args) {
        try {
            System.out.println("Starting manual CDR ingestion...");
            String inputDir = new File("input").getAbsolutePath();
            String processedDir = new File("processed").getAbsolutePath();
            
            CDRParser.processAll(inputDir, processedDir);
            System.out.println("Manual ingestion complete.");
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
