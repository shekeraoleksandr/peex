--
-- PostgreSQL database dump
--

\restrict KeGGAXKu3eRdLBN1OXTuSb8rPDo136ulmClLfoA6M54ezmfwkq63IetDkWQYraf

-- Dumped from database version 16.15
-- Dumped by pg_dump version 16.15

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: departments; Type: TABLE; Schema: public; Owner: peex_admin
--

CREATE TABLE public.departments (
    id integer NOT NULL,
    name text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE public.departments OWNER TO peex_admin;

--
-- Name: departments_id_seq; Type: SEQUENCE; Schema: public; Owner: peex_admin
--

CREATE SEQUENCE public.departments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.departments_id_seq OWNER TO peex_admin;

--
-- Name: departments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: peex_admin
--

ALTER SEQUENCE public.departments_id_seq OWNED BY public.departments.id;


--
-- Name: employees; Type: TABLE; Schema: public; Owner: peex_admin
--

CREATE TABLE public.employees (
    id integer NOT NULL,
    full_name text NOT NULL,
    email text NOT NULL,
    dept_id integer NOT NULL,
    salary numeric(10,2) NOT NULL,
    hired_at date DEFAULT CURRENT_DATE NOT NULL,
    CONSTRAINT employees_salary_check CHECK ((salary > (0)::numeric))
);


ALTER TABLE public.employees OWNER TO peex_admin;

--
-- Name: dept_salary_stats; Type: VIEW; Schema: public; Owner: peex_admin
--

CREATE VIEW public.dept_salary_stats AS
 SELECT d.name AS department,
    count(e.id) AS headcount,
    round(avg(e.salary), 2) AS avg_salary,
    max(e.salary) AS max_salary
   FROM (public.departments d
     LEFT JOIN public.employees e ON ((e.dept_id = d.id)))
  GROUP BY d.name;


ALTER VIEW public.dept_salary_stats OWNER TO peex_admin;

--
-- Name: employees_id_seq; Type: SEQUENCE; Schema: public; Owner: peex_admin
--

CREATE SEQUENCE public.employees_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employees_id_seq OWNER TO peex_admin;

--
-- Name: employees_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: peex_admin
--

ALTER SEQUENCE public.employees_id_seq OWNED BY public.employees.id;


--
-- Name: departments id; Type: DEFAULT; Schema: public; Owner: peex_admin
--

ALTER TABLE ONLY public.departments ALTER COLUMN id SET DEFAULT nextval('public.departments_id_seq'::regclass);


--
-- Name: employees id; Type: DEFAULT; Schema: public; Owner: peex_admin
--

ALTER TABLE ONLY public.employees ALTER COLUMN id SET DEFAULT nextval('public.employees_id_seq'::regclass);


--
-- Data for Name: departments; Type: TABLE DATA; Schema: public; Owner: peex_admin
--

COPY public.departments (id, name, created_at) FROM stdin;
1	Engineering	2026-09-16 17:06:30.576038+00
2	Finance	2026-09-16 17:06:30.576038+00
3	Operations	2026-09-16 17:06:30.576038+00
\.


--
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: peex_admin
--

COPY public.employees (id, full_name, email, dept_id, salary, hired_at) FROM stdin;
1	Olena Kovalenko	olena@corp.ua	1	4200.00	2021-03-01
2	Ivan Petrenko	ivan@corp.ua	1	3800.00	2022-06-15
3	Maria Shevchuk	maria@corp.ua	2	3500.00	2020-11-20
4	Andrii Bondar	andrii@corp.ua	3	3000.00	2023-01-10
5	Sofia Tkachenko	sofia@corp.ua	1	5000.00	2019-09-05
\.


--
-- Name: departments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: peex_admin
--

SELECT pg_catalog.setval('public.departments_id_seq', 3, true);


--
-- Name: employees_id_seq; Type: SEQUENCE SET; Schema: public; Owner: peex_admin
--

SELECT pg_catalog.setval('public.employees_id_seq', 5, true);


--
-- Name: departments departments_name_key; Type: CONSTRAINT; Schema: public; Owner: peex_admin
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_name_key UNIQUE (name);


--
-- Name: departments departments_pkey; Type: CONSTRAINT; Schema: public; Owner: peex_admin
--

ALTER TABLE ONLY public.departments
    ADD CONSTRAINT departments_pkey PRIMARY KEY (id);


--
-- Name: employees employees_email_key; Type: CONSTRAINT; Schema: public; Owner: peex_admin
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_email_key UNIQUE (email);


--
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: peex_admin
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (id);


--
-- Name: idx_employees_dept; Type: INDEX; Schema: public; Owner: peex_admin
--

CREATE INDEX idx_employees_dept ON public.employees USING btree (dept_id);


--
-- Name: idx_employees_salary; Type: INDEX; Schema: public; Owner: peex_admin
--

CREATE INDEX idx_employees_salary ON public.employees USING btree (salary);


--
-- Name: employees employees_dept_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: peex_admin
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_dept_id_fkey FOREIGN KEY (dept_id) REFERENCES public.departments(id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO app_reader;


--
-- Name: TABLE departments; Type: ACL; Schema: public; Owner: peex_admin
--

GRANT SELECT ON TABLE public.departments TO app_reader;


--
-- Name: TABLE employees; Type: ACL; Schema: public; Owner: peex_admin
--

GRANT SELECT ON TABLE public.employees TO app_reader;


--
-- Name: TABLE dept_salary_stats; Type: ACL; Schema: public; Owner: peex_admin
--

GRANT SELECT ON TABLE public.dept_salary_stats TO app_reader;


--
-- PostgreSQL database dump complete
--

\unrestrict KeGGAXKu3eRdLBN1OXTuSb8rPDo136ulmClLfoA6M54ezmfwkq63IetDkWQYraf

