############ stage 1: build ############
FROM maven:3.9.9-eclipse-temurin-17 AS build
WORKDIR /workspace

# Copy ONLY pom.xml first and download dependencies.
# This layer is cached and reused until pom.xml changes, so rebuilds are fast.
COPY pom.xml .
RUN mvn -B -q dependency:go-offline -DskipTests || true

COPY src ./src
RUN mvn -B -q package -DskipTests \
 && cp target/*.war /workspace/app.war

############ stage 2: runtime ############
FROM gcr.io/distroless/java17-debian12:nonroot AS runtime
WORKDIR /app

COPY --from=build --chown=nonroot:nonroot /workspace/app.war /app/app.war

ENV JAVA_TOOL_OPTIONS="-XX:MaxRAMPercentage=70 -XX:+ExitOnOutOfMemoryError" \
    SPRING_PROFILES_ACTIVE=prod \
    PORT=8080

USER nonroot
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.war"]

