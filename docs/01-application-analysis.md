# Application analysis

**Project:** Trébol eCommerce backend (`trebol-backend-monolith`)
**Scope of this document:** the application *as found in the original repository*, before any containerization or cloud work. Changes planned for production are listed in section 10 and are made in later phases.

> **Status update (November 2026):** the limitations in section 10 have since been addressed, with no change to application code beyond configuration and migrations: a `prod` Spring profile, Flyway migrations V1 to V3 (MySQL), Actuator liveness and readiness probes, secrets from Secret Manager, Swagger disabled in `prod`, and the Spring Boot parent upgraded from 3.2.9 to 3.2.12. The cloud design is described in `00-overview.md`, `02-deployment-guide.md` and `03-scaling-strategy.md`. Two environments are used: dev and prod (section 11).

---

## 1. Overview

Trébol is a monolithic eCommerce backend. It exposes a RESTful API for the store catalogue (products, categories, images, product lists), customers and people, orders and checkout, shippers, salespeople, and user/role/permission management. It also provides public endpoints for store information, customer registration, login and checkout. A separate front-end (Angular, expected on `localhost:4200`) is *not* part of this repository.

---

## 2. Technology summary

| Item | Finding | Where to verify |
|---|---|---|
| Language / runtime | Java 17 | `pom.xml` → `<java.version>17</java.version>` |
| Framework | Spring Boot **3.2.9** (Web MVC, Data JPA / Hibernate, Security, Validation) | `pom.xml` → `<parent>` |
| Build tool | Apache Maven (3.8+; 3.9 recommended) | `pom.xml` |
| Packaging | **WAR** that is also executable (embedded Tomcat, run with `java -jar`) | `pom.xml` → `<packaging>war</packaging>` + `spring-boot-maven-plugin` |
| Entry point | `org.trebol.BackendApp` (`main` method calling `SpringApplication.run`) | `src/main/java/org/trebol/BackendApp.java` |
| HTTP port | `8080` | `application.properties` → `server.port=8080` |
| Authentication | Stateless **JWT** (HS256, library JJWT 0.11.5), passwords hashed with BCrypt | `SecurityConfig`, `application.properties` (`trebol.security.*`) |
| Authorization | Method-level permissions (`@PreAuthorize`, 77 usages) backed by roles and permissions stored in the database | `src/main/java/org/trebol/api/controllers` |
| Sessions | None (`SessionCreationPolicy.STATELESS`), so any running instance can serve any request | `SecurityConfig` |
| Persistence | Spring Data JPA, QueryDSL for filtering/sorting | `org.trebol.jpa.*` |
| Default database | **H2, in-memory** (`jdbc:h2:mem:test`) seeded from `data.sql` | `application.properties` |
| Optional database | MariaDB/MySQL (driver bundled, settings are commented out in `application.properties`) | `application.properties` |
| API documentation | springdoc OpenAPI / Swagger UI (enabled by default) | `pom.xml` |
| Tests | JUnit 5 + Mockito + Spring Test; **363 tests**; JaCoCo coverage gate of 20% | `src/test`, `pom.xml` |
| Existing CI | A GitHub Actions workflow exists but sits inside `trebol-backend-monolith/.github/`, so GitHub never runs it. It also points at the original authors' SonarCloud project | `trebol-backend-monolith/.github/workflows/build.yml` |
| Observability | None built in: no Actuator, no health endpoints beyond `GET /` returning 200 | `pom.xml`, `RootController` |

### Repository layout

```
trebol-poc/
├── test-endpoints.sh                  # end-to-end smoke script for a running instance (bash + curl)
└── trebol-backend-monolith/           # the application
    ├── pom.xml
    ├── src/main/java/org/trebol/
    │   ├── BackendApp.java            # entry point
    │   ├── api/                       # REST controllers, services, request/response models
    │   ├── config/                    # Spring configuration + @ConfigurationProperties classes
    │   ├── jpa/                       # entities, repositories, CRUD services
    │   ├── security/                  # JWT filters, user details
    │   ├── payment/                   # WebPay Plus (Transbank) integration
    │   └── mailing/                   # Mailgun integration
    ├── src/main/resources/
    │   ├── application.properties     # default (dev) configuration
    │   ├── application-mailgun.empty.properties  # template for the optional mail profile
    │   ├── data.sql                   # seed data used with H2
    │   └── schema-mariadb.sql         # MariaDB schema dump
    └── src/test/                      # unit tests
```

---

## 3. How to build and run it (from scratch)

**Prerequisites:** JDK 17 and Maven 3.8+. Check with `java -version` and `mvn -v`; both must report Java 17.

```bash
cd trebol-backend-monolith

# 1. Compile, run all unit tests and the coverage gate
mvn -B verify

# 2. The packaged artifact
ls target/*.war        # trebol-backend-monolith-java17-0.2.5-SNAPSHOT.war

# 3. Run it (embedded Tomcat, in-memory H2 database)
java -jar target/trebol-backend-monolith-java17-0.2.5-SNAPSHOT.war
#    wait for the log line:  Started BackendApp in ... seconds
```

Verify from a second terminal (on Windows PowerShell use `curl.exe`, because plain `curl` is an alias for another command):

```bash
curl -i localhost:8080/               # HTTP 200
curl localhost:8080/public/about      # JSON with the store name and description
```

Run the full endpoint script from the repository root (needs bash and curl; use Git Bash or WSL on Windows):

```bash
bash test-endpoints.sh                # every check should print [PASS]
```

Stop the application with `Ctrl+C`. Because the default database is in memory, all data is lost on stop and reset on every start.

---

## 4. Dependencies

Defined in `trebol-backend-monolith/pom.xml`.

| Purpose | Libraries |
|---|---|
| Web / REST | `spring-boot-starter-web` (Tomcat, Jackson), `springdoc-openapi-starter-webmvc-ui` 2.6.0 (OpenAPI + Swagger UI) |
| Validation | `spring-boot-starter-validation` |
| Persistence | `spring-boot-starter-data-jpa` (Hibernate), `h2` 2.2.220 (runtime), `mariadb-java-client`, `querydsl-jpa` / `querydsl-apt` (jakarta classifier) |
| Security | `spring-boot-starter-security`, `jjwt-api` / `jjwt-impl` / `jjwt-jackson` 0.11.5 |
| Payments | `transbank-sdk-java` 3.0.2 (WebPay Plus) |
| Utilities | Lombok, `commons-lang3`, `unirest-java` 3.13.8 (HTTP client used by the mailing integration) |
| Testing | `spring-boot-starter-test`, `spring-security-test`, `unirest-mocks` |
| Build plugins | `maven-compiler-plugin` (Lombok annotation processing), `apt-maven-plugin` (generates QueryDSL classes), `maven-war-plugin`, `spring-boot-maven-plugin`, `jacoco-maven-plugin` (report + 20% coverage gate) |

---

## 5. Configuration and environment variables

### How configuration works

The application reads **Spring properties** from `application.properties`. The source code does not read `System.getenv` or `@Value` directly. All settings are bound through `@ConfigurationProperties` classes with these prefixes: `trebol.api`, `trebol.security`, `trebol.cors`, `trebol.validation`, `trebol.mailing`, `trebol.mailing.mailgun`, `trebol.payment.webpayplus`.

Spring Boot lets an **environment variable override any property**, so no code change is needed to externalize configuration. The naming rule is: upper-case the property name and replace `.` and `-` with `_`. For example:

| Property | Environment variable that overrides it |
|---|---|
| `spring.datasource.url` | `SPRING_DATASOURCE_URL` |
| `trebol.security.jwt-secret-key` | `TREBOL_SECURITY_JWTSECRETKEY` (hyphens are dropped or replaced, so check the binding rules for each key) |

In later phases a dedicated `prod` profile maps each setting to an explicit, simply named variable.

### Settings that matter for deployment

| Setting (property) | Purpose | Default in repo | Secret? |
|---|---|---|---|
| `server.port` | HTTP port | `8080` | no |
| `spring.datasource.url` | database JDBC URL | `jdbc:h2:mem:test` | no |
| `spring.datasource.username` / `password` | database credentials | `admin` / `admin` | **yes** |
| `spring.jpa.defer-datasource-initialization` | run `data.sql` after Hibernate creates tables (H2 mode) | `true` | no |
| `trebol.security.jwt-secret-key` | HMAC key used to sign JWTs | placeholder string | **yes** |
| `trebol.security.jwt-expiration-after-minutes/hours/days` | token lifetime | 30 minutes | no |
| `trebol.security.bcrypt-encoder-strength` | BCrypt cost factor | `10` | no |
| `trebol.security.guest-user-enabled` | allow a limited guest checkout account | `false` | no |
| `trebol.security.account-protection-enabled` / `protected-account-id` | prevent deleting the protected account (id 1) | `true` / `1` | no |
| `trebol.cors.allowed-origins` | front-end origins allowed by CORS | `localhost:4200` variants | no |
| `trebol.cors.mappings` | per-path CORS rules | long default list | no |
| `trebol.api.items-per-page`, `max-allowed-page-size` | pagination limits | `10`, `1000` | no |
| `trebol.payment.webpayplus.production` | use the real (not test) Transbank environment | `false` | no |
| `trebol.payment.webpayplus.callback-url`, `browser-redirection-url` | payment return URLs | `localhost` URLs | no |
| `trebol.mailing.*` | mail subjects and sender | example values | no |
| `trebol.mailing.mailgun.api-key`, `domain`, templates | Mailgun credentials (optional profile `mailgun`) | empty | **yes** (api-key) |
| `springdoc.*` | enable or disable Swagger UI / API docs | enabled | no |

### External files

| File | Purpose |
|---|---|
| `application.properties` | default configuration, labelled in-file as *example only, not for production* |
| `application-mailgun.empty.properties` | template: copy to `application-mailgun.properties` and activate the `mailgun` profile to enable e-mail |
| `data.sql` | seed data (roles, permissions, order statuses, demo accounts) loaded into H2 |
| `schema-mariadb.sql` | MariaDB schema, intended for creating a real database |

---

## 6. External services and data

| Dependency | Needed to run? | Notes |
|---|---|---|
| Database | Yes | H2 in-memory by default (nothing to install). MariaDB/MySQL for any shared or persistent setup |
| Transbank WebPay Plus | No | Used only for the payment step of checkout; points at Transbank's test environment unless `production=true` |
| Mailgun | No | Off unless the `mailgun` profile is activated; operations that send mail fail when it is enabled without credentials |

---

## 7. API surface (summary)

| Group | Paths | Access |
|---|---|---|
| Health / root | `GET /` | public, returns 200 |
| Public | `/public/about`, `/public/register`, `/public/login`, `/public/guest`, `/public/checkout`, `/public/checkout/validate`, `/public/receipt/*` | public |
| Account | `/account/profile`, `/access`, `/access/*` | authenticated |
| Reference data (reads) | `GET /data/billing_types`, `GET /data/products`, `GET /data/product_categories`, … | public reads for catalogue data |
| Data management | `/data/customers`, `/data/orders`, `/data/users`, `/data/user_roles`, `/data/people`, `/data/salespeople`, `/data/shippers`, `/data/images`, `/data/product_lists`, `/data/product_list_contents`, `/data/order_statuses` | permission-based (`resource:action`) |

Authentication flow: `POST /public/login` with `{"name": "...", "password": "..."}` returns the JWT in the `Authorization` response header; clients send it back in the `Authorization` request header.

---

## 8. Test results found during analysis

`mvn -B verify` was run on a Windows machine with JDK 17. Of **363** tests, **3 failed** on the unmodified code:

| Test | Cause | Fix |
|---|---|---|
| `OrdersPatchServiceImplTest.patches_date` | The service patches the order in place and returns the same object, so `assertNotEquals(existingOrder, result)` could never pass (a defect in the test, not in the application) | The test now stores the original date first and asserts the date changed to the new value; the new value is 60 seconds ahead so it cannot coincide with the original |
| `WebpayplusPaymentServiceImplTest$TestMode.fetches_payment_page_for_started_transactions` | The test called Transbank's live integration server. From this network its web firewall returned an HTML 403 page, which the SDK failed to parse (`Expected BEGIN_OBJECT but was STRING`) | The Transbank SDK call is mocked with Mockito `mockConstruction`; the assertions are unchanged |
| `WebpayplusPaymentServiceImplTest$TestMode.fetches_payment_result` | Same as above | Same as above |

Only files under `src/test` were changed; no production code was modified. A unit test that depends on a third party's live server and network policy is unreliable, and it would also make a CI pipeline fail at random.

---

## 9. Assumptions

1. The proof of concept covers the **backend API and its database only**; the Angular storefront is not deployed. CORS origins stay configurable.
2. **Payments (Transbank) and e-mail (Mailgun) stay disabled.** They need third-party accounts and are outside the scope of containerizing and scaling the API.
3. "10,000 concurrent requests" is interpreted as **10,000 concurrent virtual users** sending a mix of mostly read requests with short think times. The public read endpoints (`/public/about`, `/data/products`, `/data/product_categories`, `/data/billing_types`) are the main load targets.
4. Two environments are used: **dev** (a developer laptop, `docker compose`) and **prod** (the cloud). A separate cloud test environment was dropped to stay inside the cost limit; the pipeline's automated tests and the canary smoke test take its place. Both use the same build and differ only in configuration.
5. The target cloud is **Google Cloud Platform**.

---

## 10. Limitations and risks found (and what will be done)

| # | Finding | Risk | Planned action |
|---|---|---|---|
| 1 | Default database is **H2 in memory** | Each running instance would hold its own private data, and data is lost on restart. The app cannot scale beyond one instance | Use a shared managed database (Cloud SQL for MySQL) in test and prod, selected by a `prod` profile |
| 2 | **No health endpoints** except `GET /` | Orchestrators cannot distinguish "alive" from "ready to serve", which is needed for probes and zero-downtime deployments | Add Spring Boot Actuator with separate liveness and readiness endpoints |
| 3 | JWT secret is a **placeholder in a committed file** | Anyone can forge tokens if it is used in production | The `prod` profile has no default for the secret, so the app refuses to start without a real one; the secret lives in a secret vault |
| 4 | `data.sql` seeds demo accounts whose **password equals the username** (`admin/admin`, `manager/manager`, …) | Default credentials in production | Production data excludes demo users; the single admin password is injected at deployment from a secret |
| 5 | `schema-mariadb.sql` contains a **foreign key on `order_details` that references a non-existent table `sales`** (the table is `orders`) | Creating an order with details would fail against a real database | Fix the reference in the migration used for MySQL |
| 6 | Schema is a manual SQL dump | Not versioned, not safe when several instances start at once | Versioned database migrations (Flyway) |
| 7 | All config is in one properties file | Not suitable for several environments | Per-environment Spring profiles; every environment-specific value read from environment variables |
| 8 | Swagger UI / API docs are enabled by default | Exposes the full API surface publicly | Disabled in `prod` |
| 9 | Logs are plain text | Harder to filter and alert on in a central log system | Structured JSON logs in `prod` |
| 10 | The existing CI workflow is not active and targets someone else's SonarCloud project | No automated checks run today | New workflows at the repository root |
| 11 | BCrypt (cost 10) makes each login CPU-intensive by design | Heavy login traffic needs CPU headroom rather than more threads | Keep logins a small share of the load test; size CPU accordingly |
| 12 | `spring.jpa.open-in-view` is at the Spring default (enabled) | May hold database connections longer than necessary under heavy load | Evaluate during load-test tuning; do not change without testing |
| 13 | Three unit tests failed on the original code (see section 8) | A red build blocks CI | Fixed in test code only |

---

## 11. Environments

| | **dev** | **prod** |
|---|---|---|
| Runs on | developer laptop | Google Cloud (Cloud Run + Cloud SQL), project `itp-agentspace` |
| Spring profile | default, or `prod` with MySQL through docker-compose | `prod` |
| Database | H2 in memory, or MySQL through docker-compose | managed MySQL 8.0, SSL required, private network only |
| Secrets | local `.env` file, never committed | Secret Manager |
| Deployed by | developer | pipeline, automatically, on merge to `main` (canary, smoke test, bake check, automatic rollback) |

One build artifact moves through both environments; only configuration changes.

---

## 12. Acceptance check for this document

A reviewer with JDK 17, Maven and this repository can: run `mvn -B verify` (363 tests pass), start the application with `java -jar`, confirm `GET /` returns 200 and `GET /public/about` returns JSON, and run `test-endpoints.sh` against it, using only sections 3 and 8 of this document.
