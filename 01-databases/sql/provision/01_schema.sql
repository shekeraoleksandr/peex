-- Provision & configure a SQL database solution:
-- least-privilege role, schema with constraints, indexes, a reporting view.
\echo '>> Applying schema, constraints, indexes, view and role'

CREATE ROLE app_reader LOGIN PASSWORD 'reader_pass';

CREATE TABLE departments (
    id          SERIAL PRIMARY KEY,
    name        TEXT NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE employees (
    id          SERIAL PRIMARY KEY,
    full_name   TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE,
    dept_id     INT  NOT NULL REFERENCES departments(id),
    salary      NUMERIC(10,2) NOT NULL CHECK (salary > 0),
    hired_at    DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE INDEX idx_employees_dept   ON employees(dept_id);
CREATE INDEX idx_employees_salary ON employees(salary);

CREATE VIEW dept_salary_stats AS
SELECT d.name                         AS department,
       COUNT(e.id)                    AS headcount,
       ROUND(AVG(e.salary), 2)        AS avg_salary,
       MAX(e.salary)                  AS max_salary
FROM departments d
LEFT JOIN employees e ON e.dept_id = d.id
GROUP BY d.name;

-- Configure least-privilege access for the application role
GRANT CONNECT ON DATABASE company TO app_reader;
GRANT USAGE   ON SCHEMA public     TO app_reader;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO app_reader;
