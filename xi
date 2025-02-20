import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Request;
import software.amazon.awssdk.services.s3.model.ListObjectsV2Response;
import software.amazon.awssdk.services.s3.model.S3Object;

public class S3MultiThreadedProcessor {
    private static final Logger log = LoggerFactory.getLogger(S3MultiThreadedProcessor.class);
    private final ExecutorService fetcherPool;
    private final ExecutorService processorPool;
    private final AtomicInteger totalCount;
    private final int targetCount;
    private final String bucketName;
    private final int maxKeys;
    private final S3Client s3Client;
    private final AtomicReference<String> continuationToken;
    private final int numFetchers;
    private volatile boolean isShuttingDown = false;

    public S3MultiThreadedProcessor(int targetCount, String bucketName, int maxKeys, S3Client s3Client, 
                                    int numFetchers, int numProcessors) {
        // Validate inputs
        if (targetCount <= 0 || maxKeys <= 0 || numFetchers <= 0 || numProcessors <= 0) {
            throw new IllegalArgumentException("All counts must be positive");
        }
        if (maxKeys > 1000) { // S3 API limit
            throw new IllegalArgumentException("maxKeys cannot exceed 1000");
        }

        // Use bounded queue to prevent memory overload
        this.fetcherPool = new ThreadPoolExecutor(numFetchers, numFetchers, 0L, TimeUnit.MILLISECONDS,
                new LinkedBlockingQueue<>(100)); // Limit queue size
        this.processorPool = new ThreadPoolExecutor(numProcessors, numProcessors, 0L, TimeUnit.MILLISECONDS,
                new LinkedBlockingQueue<>(1000)); // Larger queue for processing
        this.totalCount = new AtomicInteger(0);
        this.targetCount = targetCount;
        this.bucketName = bucketName;
        this.maxKeys = maxKeys;
        this.s3Client = s3Client;
        this.continuationToken = new AtomicReference<>(null);
        this.numFetchers = numFetchers;
    }

    public void startFetchAndProcess() {
        try {
            for (int i = 0; i < numFetchers && !isShuttingDown; i++) {
                fetcherPool.submit(this::fetchAndSubmitTasks);
            }
            shutdownGracefully(); // Ensure proper cleanup
        } catch (Exception e) {
            log.error("Error starting fetch and process", e);
            shutdownNow();
            throw new RuntimeException("Failed to start processing", e);
        }
    }

    private void fetchAndSubmitTasks() {
        while (totalCount.get() < targetCount && !isShuttingDown) {
            String currentToken = continuationToken.get();
            int remaining = targetCount - totalCount.get();
            if (remaining <= 0) break;

            List<S3Object> objects = fetchBatch(currentToken);
            if (objects == null || objects.isEmpty()) {
                break;
            }

            // Trim batch if it exceeds remaining count
            List<S3Object> batchToProcess = objects;
            if (objects.size() > remaining) {
                batchToProcess = new ArrayList<>(objects.subList(0, remaining));
            }

            totalCount.addAndGet(batchToProcess.size());

            try {
                processorPool.submit(() -> processObjectsInChunks(batchToProcess));
                log.info("Fetcher {} submitted {} objects, totalCount: {}", 
                        Thread.currentThread().getName(), batchToProcess.size(), totalCount.get());
            } catch (Exception e) {
                log.error("Failed to submit batch for processing", e);
                totalCount.addAndGet(-batchToProcess.size()); // Roll back count
            }
        }
    }

    private List<S3Object> fetchBatch(String token) {
        if (isShuttingDown) return null;

        int remaining = targetCount - totalCount.get();
        if (remaining <= 0) return null;

        ListObjectsV2Request request = ListObjectsV2Request.builder()
            .bucket(bucketName)
            .maxKeys(Math.min(maxKeys, remaining)) // Dynamic adjustment
            .continuationToken(token)
            .build();

        try {
            ListObjectsV2Response response = s3Client.listObjectsV2(request);
            if (response.contents().isEmpty()) {
                continuationToken.set(null);
                return null;
            }

            List<S3Object> objects = response.contents();

            if (response.isTruncated()) {
                continuationToken.set(response.nextContinuationToken());
            } else {
                continuationToken.set(null);
            }

            return objects;
        } catch (Exception e) {
            log.error("Error fetching batch with token {}: {}", token, e.getMessage());
            continuationToken.set(null); // Reset to avoid infinite loop
            return null;
        }
    }

    private void processObjectsInChunks(List<S3Object> objects) {
        try {
            log.info("Processing {} objects in thread {}", objects.size(), Thread.currentThread().getName());
            // Simulate work - replace with actual processing
            for (S3Object obj : objects) {
                Thread.sleep(1); // More realistic per-object processing simulation
            }
        } catch (Exception e) {
            log.error("Error processing batch of {} objects", objects.size(), e);
            throw new RuntimeException("Processing failed", e);
        }
    }

    private void shutdownGracefully() {
        try {
            fetcherPool.shutdown();
            processorPool.shutdown();
            
            if (!fetcherPool.awaitTermination(10, TimeUnit.MINUTES)) {
                log.warn("Fetcher pool did not terminate in time");
                fetcherPool.shutdownNow();
            }
            if (!processorPool.awaitTermination(10, TimeUnit.MINUTES)) {
                log.warn("Processor pool did not terminate in time");
                processorPool.shutdownNow();
            }
        } catch (InterruptedException e) {
            log.error("Shutdown interrupted", e);
            Thread.currentThread().interrupt();
            shutdownNow();
        }
    }

    private void shutdownNow() {
        isShuttingDown = true;
        fetcherPool.shutdownNow();
        processorPool.shutdownNow();
    }

    public void close() {
        if (!fetcherPool.isShutdown() || !processorPool.isShutdown()) {
            shutdownGracefully();
        }
    }
}
S3MultiThreadedProcessor processor = new S3MultiThreadedProcessor(
    2_000_000,           // targetCount
    "my-bucket",         // bucketName
    1000,                // maxKeys
    S3Client.create(),   // s3Client
    10,                  // numFetchers
    16                   // numProcessors
);
processor.startFetchAndProcess();
processor.close();
