package com.example.tailsampling;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/customers")
public class CustomerController {
    private final JdbcTemplate jdbcTemplate;

    public CustomerController(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @GetMapping("/{id}")
    public Customer getCustomer(@PathVariable long id) {
        return jdbcTemplate.queryForObject(
                "SELECT id, name FROM customer WHERE id = ?",
                (resultSet, rowNumber) -> new Customer(resultSet.getLong("id"), resultSet.getString("name")),
                id);
    }
}
