-- The password hash comes from the ADMIN_PASSWORD_HASH secret via a Flyway placeholder.
INSERT INTO `app_users` (`user_id`, `user_name`, `user_password`, `user_role_id`)
VALUES (1, 'admin', '${admin_password_hash}', 1);