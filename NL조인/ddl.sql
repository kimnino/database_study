-- auto-generated definition
create table AGENT
(
    agent_id  int         not null
        primary key,
    name      varchar(40) null,
    hire_date date        null,
    dept_code varchar(20) null
);

create index ix_hire_date
    on AGENT (hire_date);

-- auto-generated definition
create table PLAYER
(
    player_id        int         not null
        primary key,
    name             varchar(40) null,
    tel              varchar(40) null,
    manager_agent_id int         null,
    constraint player_ibfk_1
        foreign key (manager_agent_id) references AGENT (agent_id)
);

create index manager_agent_id
    on PLAYER (manager_agent_id);

create index ix_value
    on PLAYER (value);


