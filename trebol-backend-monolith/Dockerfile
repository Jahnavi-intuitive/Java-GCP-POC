# syntax=docker/dockerfile:1.7
############ stage 1: build ############
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /workspace

# Copy ONLY pom.xml first and download dependencies.
# The layer is reused until pom.xml changes. The BuildKit cache mount also keeps
# ~/.m2 between builds on the same builder, so even a pom change re-downloads little.
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2 mvn -B -q dependency:go-offline -DskipTests

COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B -q package -DskipTests \
 && java -Djarmode=layertools -jar target/*.war extract --destination /workspace/layers \
 # CDS can only archive classes from jars, so package the app classes as a jar.
 && jar cf /workspace/app-classes.jar -C /workspace/layers/application/WEB-INF/classes . \
 # lombok is compile-time only: not needed at runtime. swagger-ui is kept so Swagger UI can be enabled in prod (SWAGGER_ENABLED=true).
 && rm -f /workspace/layers/dependencies/WEB-INF/lib/lombok-*.jar

############ stage 2: runtime ############
FROM gcr.io/distroless/java17-debian12:nonroot AS runtime
WORKDIR /app

# Only the layers that are actually on the classpath. The Spring Boot loader and
# snapshot-dependency layers are unused (we start the main class directly), so they
# are not copied. --link makes each layer independent: changing the small app layer
# never invalidates the large dependency layer above it.
COPY --link --chown=65532:65532 --from=build /workspace/layers/dependencies/ ./
COPY --link --chown=65532:65532 --from=build /workspace/app-classes.jar ./app-classes.jar

# One classpath definition, used by the CDS training run and by the entrypoint.
# CDS requires the classpath to be identical in both.
ENV CLASSPATH="/app/app-classes.jar:/app/WEB-INF/lib/*:/app/WEB-INF/lib-provided/*"

# AppCDS: a training run (context refresh only, in-memory H2, no network) records the
# loaded classes in an archive that the JVM maps at startup instead of parsing and
# verifying thousands of classes. Built with the same JVM that runs the app.
USER root
RUN ["java", \
     "-XX:ArchiveClassesAtExit=/app/app-cds.jsa", \
     "-XX:+UseSerialGC", \
     "-Dspring.context.exit=onRefresh", \
     "-Dspring.profiles.active=default", \
     "-Dserver.port=0", \
     "org.trebol.BackendApp"]

# JVM tuning for a small (1-2 vCPU) Cloud Run container:
# - SerialGC: lowest overhead and fastest start on small heaps
# - TieredStopAtLevel=1: C1 only, C2 threads would compete with requests for the vCPU
# - SharedArchiveFile: the AppCDS archive built above
# - Xss512k: smaller thread stacks, Tomcat runs up to 200 threads
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError \
 -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss512k \
 -XX:SharedArchiveFile=/app/app-cds.jsa -Xshare:auto" \
    SPRING_PROFILES_ACTIVE=prod \
    PORT=8080

USER nonroot
EXPOSE 8080

ENTRYPOINT ["java", "org.trebol.BackendApp"]
