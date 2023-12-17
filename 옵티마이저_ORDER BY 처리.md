# 옵티마이저란...?
기본 데이터를 비교해 최적의 실행 계획을 수립하는 작업을 담당한다.

# 옵티마이저 ORDER BY 처리
정렬을 처리하는 방법은 **1)인덱스를 이용하는 방법**, **2)쿼리가 실행될 때 'Filesort'라는 별도의 처리를 이용하는 방법**

||*장점*|*단점*|
|:--|--|--|
|인덱스|INSERT, UPDATE, DELETE 쿼리가 실행될 때 이미 인덱스가 정렬돼 있어서 순서대로 읽기만 하면 되므로 매우 빠르다.|INSERT,UPDATE,DELETE 작업 시 부가적인 인덱스 추가/삭제 작업이 필요하므로 느리고,<br> 인덱스 때문에 공간이 더 많이 필요하다. 인덱스가 늘어날 수록 버퍼 풀을 위한 메모리가 많이 필요하다.|
|Filesort|인덱스를 생성하지 않아도 되므로 인덱스의 단점이 장점이 된다. 정렬할 레코드가 많지 않으면 메모리에서 Filesort가 처리되므로 충분히 빠르다.|정렬 작업시 쿼리 실행 시 처리되므로 레코드 대상 건수가 많아질수록 쿼리 응답 속도가 느리다.|


### 모든 정렬을 인덱스를 이용하도록 튜닝하기 불가능한 이유
1. 정렬 기준이 너무 많아서 요건별로 모두 인덱스를 생성하는 것이 불가능한 경우
2. GROUP BY의 결과 또는 DISTINCT 같은 처리의 결과가 정렬해야 하는 경우
3. UNION의 결과와 같이 임시 테이블의 결과를 다시 정렬해야 하는 경우
4. 랜덤하게 결과 레코드를 가져와야 하는 경우

----- 
MySQL 서버에서 인덱스를 이용하지 않고 별도의 정렬 처리를 수행했는지는 실행 계획의 Extra 칼럼에 'Using filesort' 가 표시되는지 여부로 파악이 가능하다.
![image](https://github.com/kimnino/database_study/assets/140059002/579e53de-1959-4e3a-881e-716afe0cdb16)

## 소트 버퍼
MySQL은 정렬을 수행하기 위해 별도의 메모리 공간을 할당받아서 사용 --> 이 메모리 공간을 **소트 버퍼(Sort buffer)**
소트 버퍼는 정렬이 필요한 경우에만 할당되고, 소트 버퍼는 쿼리가 실행이 완료되면 즉시 시스템에 반납된다.

### 정렬이 왜 문제가 되는가
정렬해야 할 레코드의 건수가 소트 버퍼로 할당된 공간보다 크다면 -> 레코드를 여러 조각으로 나눠서 처리하고, 이 과정에서 임시 저장을 위해서 디스크를 사용
1. 소트 버퍼에서 정렬을 수행
2. 그 결과를 임시로 디스크에 기록
3. 다음 레코드를 가져와서 다시 정렬해서 반복적으로 디스크에 임시 저장
4. 버퍼 크기만큼 정렬된 레코드를 다시 병합하면서 정렬을 수행 (해당 병합과정을 멀티 머지)
5. 이러한 모든 작업들이 디스크의 쓰기와 읽기를 유발한다.

MySQL은 글로벌 메모리 영역과 세션(로컬) 메모리 영역으로 나눠서 생각할 수 있다.
정렬을 위해 할당하는 소트 버퍼는 세션 메모리 영역에 해당한다.
정렬 작업이 많다 -> 소트 버퍼로 소비되는 메모리 공간이 커짐 -> 메모리 부족 현상을 겪을 수 있다.

    소트 버퍼를 크게 설정해서 빠른 성능을 얻을 수는 없지만, 디스크의 읽기와 쓰기 사용량을 줄일 수 있다.
    MySQL 서버의 데이터가 많거나, 디스크의 I/O 성능이 낮은 장비라면 소트 버퍼의 크기를 더 크게 설정하면 도움이 될 수 있다.
    하지만 너무 크게 설정하면 서버의 메모리가 부족해져서 MySQL 서버가 메모리 부족을 겪을 수 있다.

## 정렬 알고리즘
```
-- 옵티마이저 트레이스 활성화
SET OPTIMIZER_TRACE="enabled=on", END_MARKERS_IN_JSON=on;
SET OPTIMIZER_TRACE_MAX_MEM_SIZE=1000000;

-- 쿼리실행
SELECT * FROM employees ORDER BY last_name LIMIT 100000, 1;

-- 트레이스 내용 확인 ( DataGrip으로는 내용이 안나와서 직접 MySQL 서버에서 실행 )
SELECT * FROM information_schema.OPTIMIZER_TRACE;
            ...
            "filesort_priority_queue_optimization": {
              "limit": 100001
            } /* filesort_priority_queue_optimization */,
            "filesort_execution": [
            ] /* filesort_execution */,
            "filesort_summary": {
              "memory_available": 262144,
              "key_size": 264,
              "row_size": 401,
              "max_rows_per_buffer": 653,
              "num_rows_estimate": 299202,
              "num_rows_found": 300024,
              "num_initial_chunks_spilled_to_disk": 78,
              "peak_memory_used": 294912,
              "sort_algorithm": "std::sort",
              "sort_mode": "<varlen_sort_key, packed_additional_fields>"
            } /* filesort_summary */
            ...
```
"filesort_summary" 섹션의 "sort_algorithm" 필드에 정렬 알고리즘이 표시되고, 
"sort_mode" 필드에는 "<varlen_sort_key, packed_additional_fields>"가 표시됨.
* <sort_key, rowid> : 정렬 키와 레코드의 로우 아이디(ROW ID)만 가져와서 정렬하는 방식 **싱글 패스 정렬 방식**
* <sort_key, additional_fields> : 정렬 키와 레코드 전체를 가져와서 정렬하는 방식으로, 레코드의 칼럼들은 고정 사이즈로 메모리의 저장 **투 패스 정렬 방식**
* <sort_key, packed_additional_fields> : 정렬 키와 레코드 전체를 가져와서 정렬하는 방식으로, 레코드의 칼럼들은 가변 사이즈로 저장 **투 패스 정렬 방식**

### 싱글 패스 정렬 방식
**싱글 패스(Single-pass)** : 소트 버퍼에 정렬 기준 칼럼을 포함해 SELECT 대상이 되는 칼럼 전부를 담아서 정렬을 수행하는 방식

```
  SELECT emp_no, first_name, last_name
  FROM employees
  ORDER BY first_name;
```
위 쿼리와 같이 first_name으로 정렬해서 emp_no, first_name, last_name을 SELECT하는 쿼리로
처음 employees 테이블을 읽을 때 정렬에 필요하지 않는 last_name 칼럼까지 전부 읽어서 소트 버퍼에 담고 정렬을 수행 ( 그럼 아마 소트 버퍼에 담는 내용이 커지 메모리 공간을 더 차지? )
싱글 패스 방식은 정렬 대상 레코드의 크기나 건수가 작은 경우 빠른 성능을 보인다.

### 투 패스 정렬 방식
**투 패스(Two-pass)** : 정렬 대상 칼럼과 프라이머리 키 값만 소트 버퍼에 담아서 정렬을 수행하고, 정렬된 순서대로 다시 프라이머리 키로 테이블을 읽어서 SELECT할 칼럼을 가져오는 정렬 방식
처음 employees 테이블을 읽을 때 정렬에 필요한 first_name 칼럼과 프라이머리 키인 emp_no만 읽어서 정렬을 수행
정렬이 완료되면 그 결과 순서대로 employees 테이블에서 한 번 더 읽어서 last_name을 가져온다.
투 패스 방식은 정렬 대상 레코드의 크기나 건수가 상당히 많은 경우 효율적이라고 볼 수 있다.

    투 패스 방식은 테이블을 두 번 읽어야 하기 때문에 상당히 불합리하고, 반면 싱글 패스는 이러한 불합리함은 없다.
    하지만 싱글 패스는 더 많은 소트 버퍼 공간이 필요하다.

**그럼 일반으로는 싱글 패스를 사용하면 좋겠지만 투 패스를 사용하는 경우는?**

    - 레코드의 크기가 max_length_for_sort_data 시스템 변수에 설정된 값보다 클 때
    - BLOB이나 TEXT 타입의 칼럼이 SELECT 대상에 포함할 때

```
  SELECT 쿼리에서 꼭 필요한 칼럼만 조회하지 않고, 모든 칼럼(*)을 가져오도록 개발할 때가 많다.
  하지만 이는 정렬 버퍼를 몇 배에서 몇십 배까지 비효율적으로 사용할 가능성이 크다. SELECT 쿼리에서 꼭 필요한 칼럼만 조회하도록
  쿼리를 작성하는 것이 좋다고 권장하는 것이 바론 이런 이유이고, 꼭 정렬 버퍼 뿐만 아니라 임시 테이블이 필요한 쿼리에서도 영향을 미친다.
  그럼 우리는 업무에서 findAll을 줄일 수 있는 케이스가 있을까..?
```


## 정렬 처리 방법
쿼리에 ORDER BY가 사용되면 반드시 다음 3가지 처리 방법 중 하나로 정렬이 처리된다.
일반적으로 아래로 내려 갈수록 처리 속도는 떨어진다.
|정렬 처리 방법|실행 계획의 Extra 칼럼 내용|
|--|--|
|인덱스를 사용한 정렬|별도 표기 없음|
|조인에서 드라이빙 테이블만 정렬|"Using filesort" 메시지가 표시됨|
|조인에서 조인 결과를 임시 테이블로 저장 후 정렬|"Using temporary; Using filesort" 메시지가 표시됨|
```
    1. 옵티마이저는 정렬 처리를 위해 인덱스를 이용할 수 있는지 검토
    2. 인덱스를 이용할 수 있으면, 인덱스 순서대로 읽어서 결과를 반환
    3. 인덱스를 이용할 수 없으면, WHERE 조건에 일치하는 레코드를 검색해 정렬 버퍼에 저장하면서 정렬을 처리(Filesort)
    4. 이때, 옵티마이저는 정렬 대상 레코드를 최소화 하기 위해서 2가지 방법 중 하나를 선택
        1) 조인의 드라이빙 테이블만 정렬한 다음에 조인을 수행
        2) 조인이 끝나고 일치하는 레코드를 모두 가져온 후 정렬을 수행
    5. 일반적으로 조인이 수행되면 레코드 건수와 레코드의 크기는 거의 배수로 불어나서 가능하면 드라이빙 테이블만 정렬하는게 효율적
```

### 인덱스를 이용한 정렬
ORDER BY에 명신된 칼럼이 반드시 제일 먼저 읽는 테이블에 속하고, ORDER BY의 순서대로 생성된 인덱스가 있어야 한다.
또한 WHERE절에 첫 번째로 읽는 테이블의 칼럼에 대한 조건이 있다면 그 조건과 ORDER BY는 같은 인덱스를 사용할 수 있어야 한다.
B-Tree 계열의 인덱스여야 한다. **스트리밍 방식**
```
SELECT
    *
FROM
    employees e, salaries s
WHERE
    s.emp_no=e.emp_no
    AND e.emp_no BETWEEN 100002 AND 100020
ORDER BY
    e.emp_no;
-- emp_no 칼럼으로 정렬이 필요한데, 인덱스를 사용하면 자동으로 정렬 된다고
-- 일부러 ORDER BY emp_no를 제거하는 것은 좋지 않은 선택이다.

SELECT
    *
FROM
    employees e, salaries s
WHERE
    s.emp_no=e.emp_no
    AND e.emp_no BETWEEN 100002 AND 100020;
```
MySQL 서버는 정렬을 인덱스로 처리할 수 있는 경우 부가적으로 불필요한 정렬 작업을 수행하지 않는다.
그래서 인덱스로 정렬이 처리될 때는 ORDER BY가 쿼리에 명시된다고 해서 작업량이 더 늘지는 않는다.
그러니 혹시나 쿼리의 실행 계획이 조금 변경된다면 ORDER BY가 명시되지 않는 쿼리는 결과를 기대했던 순서대로 가져오지 못 할 수 있다.
그러니 ORDER BY를 명시해주자.

### 조인의 드라이빙 테이블만 정렬
일반적으로 조인이 수행되면 결과 레코드의 건수가 몇 배로 불어나고, 레코드 하나하나의 크기도 늘어난다.
그래서 조인을 실행하기 전에 첫 번째 테이블의 레코드를 먼저 정렬한 다음 조인을 실행하는 것이 정렬의 차선책이 된다.
**버퍼링 방식**
```
SELECT
    *
FROM
    employees e, salaries s
WHERE
    s.emp_no = e.emp_no
    AND e.emp_no BETWEEN 100002 AND 100010
ORDER BY
    e.last_name;
```
WHERE 절이 다음 2가지 조건을 갖추고 있기 때문에 옵티마이저는 employees 테이블을 드라이빙 테이블로 선택할 것이다.
* WHERE 절의 검색 조건("emp_no BETWEEN 100002 AND 100010")은 employees 테이블의 프라이머리 키를 이용해 검색하면 작업량을 줄일 수 있다.
* 드리븐 테이블(salaries)의 조인 칼럼인 emp_no 칼럼에 인덱스가 있다.

검색은 인덱스 레인지 스캔으로 처리할 수 있지만 ORDER BY 절에 명시된 칼럼은 employees 테이블의 프라이머리 키와 전혀 연관이 없다.
그런데 ORDER BY 절의 정렬기준 칼럼이 드라이빙 테이블에 포함된 칼럼임을 알 수 있다. 그래서 옵티마이저는 드라이빙 테이블만 검색해서 정렬하고, 그 결과와 드리븐 테이블을 조인.

그래서 위에 쿼리에 상세한 과정은
```
    1. 인덱스를 이용해 "emp_no BETWEEN 100002 AND 100010" 조건을 만족하는 9건을 검색
    2. 검색된 결과를 last_name 칼럼으로 정렬을 수행(Filesort)
    3. 정렬된 결과를 순서대로 읽으면서 salaries 테이블과 조인을 수행해 86건의 최종 결과를 가져옴
```
  
### 임시 테이블을 이용한 정렬
2개 이상의 테이블을 조인해서 그 결과를 정렬해야 한다면 임시 테이블이 필요할 수도 있다.
"조인의 드라이빙 테이블만 정렬"을 제외한 패턴의 쿼리는 항상 조인의 결과를 임시 테이블에 저장하고, 그 결과를 다시 정렬하는 과정을 거친다.
가장 느린 정렬 방법이다. **버퍼링 방식**
```
SELECT
    *
FROM
    employees e, salaries s
WHERE
    s.emp_no = e.emp_no
    AND e.emp_no BETWEEN 100002 AND 100010
ORDER BY
    s.salary;
```
ORDER BY 절의 정렬 기준 칼럼이 드리븐 테이블에 있는 칼럼이다. 즉 정렬이 수행되기 전에 salaries 테이블을 읽어야 하므로 이 쿼리는 조인된 데이터를 가지고 정렬할 수밖에 없다.
![image](https://github.com/kimnino/database_study/assets/140059002/658de94a-1df9-4567-9724-64de3de66b79)
"Using temporary; Using filesort"라는 코멘트가 표시 -> 조인의 결과를 임시 테이블에 저장하고, 그 결과를 다시 정렬 처리했음을 의미

### 정렬 처리 방법의 성능 비교
ORDER BY나 GROUP BY 때문에 쿼리가 느려지는 경우가 자주 발생한다.
쿼리에서 인덱스를 사용하지 못하는 정렬이나 그루핑 작업이 왜 느리게 작동할 수 밖에 없는 이유와 처리되는 방법을 2가지로 구분

#### 스트리밍 방식
서버 쪽에서 처리할 데이터가 얼마인지에 관계없이 조건에 일차하는 레코드가 **검색될때마다 바로바로 클라이언트로 전송해주는** 방식. 

#### 버퍼링 방식
ORDER BY나 GROUP BY 같은 처리는 쿼리의 결과가 스트리밍되는 것을 불가능하게 한다.
우선 WHERE 조건에 일치하는 모든 레코드를 가져온 후, 정렬하거나 그루핑해서 차례대로 보내야 하기 때문이다.
서버에서 모든 레코드를 검색하고 정렬 작업을 하는 동안 클라이언트는 대기, 응답속도가 느려진다.
그렇기 때문에 스트리밍의 반대 표현으로 버퍼링이라고 표현됨.

## 정렬 관련 상태 변수
MySQL 서버는 처리하는 주요 작업에 대해서는 해당 작업의 실행 횟수를 상태 변수로 저장한다.

![image](https://github.com/kimnino/database_study/assets/140059002/cfef1c1f-9e91-42ef-811f-514823c52bb5)
```
    - Sort_merge_passes는 멀티 머지 처리 횟수를 의미
    - Sort_range는 인덱스 레인지 스캔을 통해 검색된 결과에 대한 정렬 작업 횟수다.
    - Sort_rows는 지금까지 정렬한 전체 레코드 건수를 의미
    - Sort_scan은 풀 테이블 스캔을 통해 검색된 결과에 대한 정렬 작업 횟수다.
```

![image](https://github.com/kimnino/database_study/assets/140059002/7c119fdd-a06f-4714-9478-b27e72e70f0d)

```
    salary 칼럼은 인덱싱 처리가 되지않아 풀 테이블 스캔이 일어나서 Sort_scan의 숫자가 늘어난다.
```

![image](https://github.com/kimnino/database_study/assets/140059002/3064e3ea-201c-4a48-b2d0-3a5951c07c08)

```
    salary 칼럼에 인덱스를 생성하고, Sort_range의 숫자가 늘어나는걸 기대한 실습이였는데, Sort_scan이 늘어났다... 왜그런거죠?
```



