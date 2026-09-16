package com.example.tailsampling;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/test")
public class TestController {
    private final JdbcTemplate jdbcTemplate;

    public TestController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @GetMapping("/ok")
    public String ok() {
        jdbcTemplate.queryForObject("SELECT pg_sleep(0.05)", String.class);
        return "OK";
    }

    @GetMapping("/slow")
    public String slow() {
        jdbcTemplate.queryForObject("SELECT pg_sleep(6)", String.class);
        return "SLOW";
    }

    @GetMapping("/db-error")
    public String dbError() {
        jdbcTemplate.queryForObject("SELECT * FROM table_that_does_not_exist", String.class);
        return "never reached";
    }
}
