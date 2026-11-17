############ stage 1: build ############
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /workspace

# Copy ONLY pom.xml first and download dependencies.
# This layer is cached and reused until pom.xml changes, so rebuilds are fast.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline -DskipTests

COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/*.war /workspace/app.war \
 && java -Djarmode=layertools -jar /workspace/app.war extract --destination /workspace/layers  && jar cf /workspace/app-classes.jar -C /workspace/layers/application/WEB-INF/classes .  && rm -rf /workspace/layers/application/WEB-INF/classes

############ stage 2: runtime ############
FROM gcr.io/distroless/java17-debian12:nonroot AS runtime
WORKDIR /app

# Exploded layers: dependencies change rarely, so they stay cached and the
# image pushes/pulls only the small "application" layer on a code change.
COPY --from=build --chown=nonroot:nonroot /workspace/layers/dependencies/ ./
COPY --from=build --chown=nonroot:nonroot /workspace/layers/spring-boot-loader/ ./
COPY --from=build --chown=nonroot:nonroot /workspace/layers/snapshot-dependencies/ ./
COPY --from=build --chown=nonroot:nonroot /workspace/layers/application/ ./
# CDS can only archive classes from jars, not from a classes directory,
# so the application classes are packaged as a jar in the build stage.
COPY --from=build --chown=nonroot:nonroot /workspace/app-classes.jar ./app-classes.jar

# AppCDS: a training run (context refresh only, in-memory H2, no network)
# records the loaded classes into an archive. At runtime the JVM maps the
# archive instead of parsing and verifying thousands of classes, which cuts
# cold-start time. Built with the SAME JVM that runs the app, as CDS requires.
# The classpath string must be identical here and in ENTRYPOINT.
USER root
RUN ["java", \
     "-XX:ArchiveClassesAtExit=/app/app-cds.jsa", \
     "-XX:+UseSerialGC", \
     "-Dspring.context.exit=onRefresh", \
     "-Dspring.profiles.active=default", \
     "-Dserver.port=0", \
     "-cp", "/app/app-classes.jar:/app/WEB-INF/lib/*:/app/WEB-INF/lib-provided/*", \
     "org.trebol.BackendApp"]

# JVM tuning for a small (1-2 vCPU) Cloud Run container:
# - SerialGC: lowest overhead and fastest start on small heaps
# - TieredStopAtLevel=1: C1 only; the C2 compiler threads otherwise compete
#   with request handling for the single vCPU while the instance is warming up
# - SharedArchiveFile: the AppCDS archive built above
# - Xss512k: smaller thread stacks, Tomcat runs up to 200 threads
ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError \
 -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -Xss512k \
 -XX:SharedArchiveFile=/app/app-cds.jsa -Xshare:auto" \
    SPRING_PROFILES_ACTIVE=prod \
    PORT=8080

USER nonroot
EXPOSE 8080

ENTRYPOINT ["java", "-cp", "/app/app-classes.jar:/app/WEB-INF/lib/*:/app/WEB-INF/lib-provided/*", "org.trebol.BackendApp"]
