EXPLAIN SELECT col1, col2 FROM tb_test GROUP BY col1, col2;
EXPLAIN SELECT DISTINCT col1 FROM tb_test;
EXPLAIN SELECT col1, MIN(col2) FROM tb_test GROUP BY col1;
EXPLAIN SELECT MAX(col3), MIN(col3),col1, col2 FROM tb_test WHERE col1 < 2 GROUP BY col1, col2;
EXPLAIN SELECT  col1, col2 FROM tb_test WHERE col2 > 2 GROUP BY col1, col2;
EXPLAIN SELECT col2 FROM tb_test WHERE col1 < 2 GROUP BY col1, col2;
EXPLAIN SELECT col1, col2 FROM tb_test WHERE col3 = 2 GROUP BY col1, col2;


-- MIN()과 MAX() 이외의 집합 함수는 루스 인덱스 스캔을 사용 못한다.
SELECT col1, SUM(col2) FROM tb_test GROUP BY col1;
-- GROUP BY에 사용된 칼럼이 인덱스 구성 컬럼의 왼쪽부터 일치하지 않으면 사용 불가
-- SELECT 절의 칼럼이 GROUP BY 절과 일치하지 않아 사용 불가
SELECT col1, col2 FROM tb_test GROUP BY col2, col3;
SELECT col1, col3 FROM tb_test GROUP BY col1, col2;

EXPLAIN SELECT e.last_name, AVG(s.salary) FROM employees e, salaries s WHERE s.emp_no=e.emp_no GROUP BY e.last_name;

SELECT DISTINCT emp_no FROM salaries;
SELECT emp_no FROM salaries GROUP BY emp_no;

SELECT DISTINCT first_name, last_name FROM employees;
SELECT DISTINCT (first_name), last_name FROM employees;

EXPLAIN SELECT COUNT(DISTINCT s.salary) FROM employees e, salaries s WHERE e.emp_no=s.emp_no AND s.emp_no BETWEEN 100001 AND 100100;

EXPLAIN SELECT COUNT(DISTINCT emp_no) FROM employees;
EXPLAIN SELECT COUNT(DISTINCT emp_no) FROM dept_emp GROUP BY dept_no;

SELECT DISTINCT first_name, last_name
FROM employees
WHERE emp_no BETWEEN 10001 AND 10200;

SELECT COUNT(DISTINCT first_name), COUNT(DISTINCT last_name)
FROM employees
WHERE emp_no BETWEEN 10001 AND 10200;

SELECT COUNT(DISTINCT first_name, last_name)
FROM employees
WHERE emp_no BETWEEN 10001 AND 10200;