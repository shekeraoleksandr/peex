-- Execute SQL query to retrieve data: JOIN + filter + sort
SELECT e.full_name, d.name AS department, e.salary
FROM employees e
JOIN departments d ON d.id = e.dept_id
WHERE e.salary > 3500
ORDER BY e.salary DESC;

-- Retrieve aggregated data through the reporting view
SELECT * FROM dept_salary_stats ORDER BY avg_salary DESC;
