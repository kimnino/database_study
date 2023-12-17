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

### 투 패스 정렬 방식
**투 패스(Two-pass)** : 정렬 대상 칼럼과 프라이머리 키 값만 소트 버퍼에 담아서 정렬을 수행하고, 정렬된 순서대로 다시 프라이머리 키로 테이블을 읽어서 SELECT할 칼럼을 가져오는 정렬 방식
처음 employees 테이블을 읽을 때 정렬에 필요한 first_name 칼럼과 프라이머리 키인 emp_no만 읽어서 정렬을 수행
정렬이 완료되면 그 결과 순서대로 employees 테이블에서 한 번 더 읽어서 last_name을 가져온다.

    투 패스 방식은 테이블을 두 번 읽어야 하기 때문에 상당히 불합리하고, 반면 싱글 패스는 이러한 불합리함은 없다.
    하지만 싱글 패스는 더 많은 소트 버퍼 공간이 필요하다.

**그럼 일반으로는 싱글 패스를 사용하면 좋겠지만 투 패스를 사용하는 경우는?**

    - 레코드의 크기가 max_length_for_sort_data 시스템 변수에 설정된 값보다 클 때
    - BLOB이나 TEXT 타입의 칼럼이 SELECT 대상에 포함할 때


    









