# Fragile Haul online server: friends, invites, parties and co-op relay.
# Listens on $PORT (Render sets it; default 8080).
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY fragile-haul-server.jar /app/server.jar
ENV PORT=8080
EXPOSE 8080
CMD ["java", "-Xmx256m", "-jar", "/app/server.jar"]
