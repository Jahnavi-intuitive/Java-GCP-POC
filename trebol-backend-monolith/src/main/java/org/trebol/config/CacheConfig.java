package org.trebol.config;

import com.github.benmanes.caffeine.cache.Caffeine;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.caffeine.CaffeineCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * Short-lived in-memory cache for read-mostly public data (catalogue lists, about).
 * Each instance keeps its own copy. Writes evict the local copy at once and the
 * TTL bounds how long other instances can serve older data.
 */
@Configuration
@EnableCaching
public class CacheConfig {

    public static final String CATALOGUE = "catalogue";

    @Bean
    public CacheManager cacheManager(@Value("${trebol.cache.ttl-seconds:30}") long ttlSeconds) {
        CaffeineCacheManager manager = new CaffeineCacheManager(CATALOGUE);
        manager.setCaffeine(Caffeine.newBuilder()
            .expireAfterWrite(Duration.ofSeconds(ttlSeconds))
            .maximumSize(2000));
        return manager;
    }
}
