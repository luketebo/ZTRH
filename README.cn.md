# ZTRH · 开发传输变更交接清单

**中文** ｜ [English](README.md)

> 事务码 **`ZTRH`** ｜ 程序 **`ZTR_DEVELOPER_HANDOVER`** ｜ ALV 结构 **`ZTR_DEVELOPER_ALV`**

把某个开发人员名下的**传输请求（请求 / 任务）**和它们**包含的开发对象**（程序、函数、类、表、域、BADI、结构……）拉平成一张清单，用来回答交接时最难回答的三个问题：

1. 这个人在这套系统里到底改过什么？
2. 这些东西分散在哪些请求里？
3. 每个对象属于哪个包、最后一次改动是什么时候？

---

## 1. 为什么做这个报表（背景）

- 项目周期一长，**改过的代码容易被遗忘**，也记不清具体逻辑落在了哪个程序 / 函数里。
- 但 SAP 的**传输请求几乎不会被删除**——它天然就是一份可信、完整、带时间戳的「变更台账」。
- 交接、审计、回归排查时，缺的不是数据，而是**一个按开发者维度把台账翻出来的入口**。

所以本程序的思路是：**以 TR 为主线，反向索引对象，按开发者（`AS4USER`）维度汇总输出。**

## 2. 功能概览

- 一条 SELECT 打通 `E070 → E071 → TADIR ← E07T`，一次性取出请求头 + 对象明细。
- `SALV` 输出：列宽自适应、斑马纹、全量工具条按钮、行/列多选。
- 默认只取**当前登录用户**（`sy-uname`）名下的请求与任务，可一键导出/排序/筛选，直接当作交接附件。

## 3. 创建的对象


| 类型          | 名称                     | 描述                               |
| --------------- | -------------------------- | ------------------------------------ |
| 事务码        | `ZTRH`                   | 报表入口                           |
| 程序          | `ZTR_DEVELOPER_HANDOVER` | 开发传输变更交接清单（可执行报表） |
| 结构 / 表类型 | `ZTR_DEVELOPER_ALV`      | 开发传输变更交接清单 ALV 输出结构  |

## 4. ALV 输出结构


| 字段名     | 类型                        | 描述                                        | 数据来源                                |
| ------------ | ----------------------------- | --------------------------------------------- | ----------------------------------------- |
| `TRUSER`   | `TRUSER`                    | 请求/任务的所有者                           | `E070-AS4USER`                          |
| `TRKORR`   | `TRKORR`                    | 请求/任务                                   | `E070-TRKORR`                           |
| `AS4TEXT`  | `TRORDERTXT`                | 请求的简短描述                              | `E07T-AS4TEXT`（按 `LANGU = sy-langu`） |
| `AS4DATE`  | `TRDATE`                    | 上次更改日期                                | `E070-AS4DATE`                          |
| `AS4TIME`  | `AS4TIME`                   | 上次更改时间                                | `E070-AS4TIME`                          |
| `DEVCLASS` | `DEVCLASS`                  | 包                                          | `TADIR-DEVCLASS`                        |
| `OBJECT`   | `TROBJTYPE`                 | 对象类型                                    | `E071-OBJECT`                           |
| `OBJ_NAME` | `TROBJ_NAME_WITH_LOWERCASE` | 对象列表中的对象名称                        | `E071-OBJ_NAME`                         |
| `OBJFUNC`  | `OBJFUNC`                   | 对象功能（`K` 锁定 / `D` 删除 / 空 = 修改） | `E071-OBJFUNC`                          |
| `PGMID`    | `PGMID`                     | 请求和任务中的程序标识（`R3TR` / `LIMU`）   | `E071-PGMID`                            |

> 结构里的字段名与 SELECT 的别名**必须严格一一对应**，因为 v0.1 用的是 `MOVE-CORRESPONDING`——名字不一致时会**静默丢字段**，不会报错。这是本项目最容易踩的坑。

## 5. 取数逻辑与关键点

```text
E070 (请求头/所有者)  ──INNER──  E071 (请求中的对象)
                              └──INNER──  TADIR (对象 → 包 DEVCLASS，同 PGMID/OBJECT/OBJ_NAME)
E07T (请求描述，按语言)  ──LEFT───  E070
WHERE E070-AS4USER = sy-uname
```

- **`E07T` 用 LEFT JOIN + `LANGU = @sy-langu`**：描述缺失时不应把整行请求丢掉；但也会出现 `AS4TEXT` 为空的情况，必要时可回退取任意语言或在 ALV 中显示占位符。
- **`TADIR` 用 INNER JOIN**：拿得到 `DEVCLASS`，但会**丢掉不在 TADIR 里的对象**（部分系统对象、跨系统生成物）。若以「完整性」优先，应改为 LEFT JOIN 或直接以 `E071` 为主表。
- **`E070` 同时包含请求与任务**：同一请求下的任务对象会一并出现，排序时应按 `TRKORR` 归组，避免误读。
- **未过滤请求状态/类型**：`E070-TRSTATUS`（如 `D` 可修改 / `R` 已释放）与 `TRFUNCTION` 目前未进输出，v0.2 计划补齐（见路线图）。
- **权限**：跨用户查询他人请求需要相应的 CTS 权限，否则会取不到或看到不完整的数据。

## 6. 界面参考

需求分析示意（用户 → 对象类型 → 所属请求 的归属关系，取自设计阶段的分析表）：

![分析示意](docs/images/design-preview.png)

目标 ALV 展示形态：**请求头信息 + 对象明细**平铺在一张可排序、可导出的清单里，同一请求的多行对象靠 `TRKORR` 排序归组。

## 7. 标准程序分析：`TR_PRESENT_REQUESTS_ORGANIZER` / `RDDM0001`

**现象**

- 在 `SE38` 打开程序，**看不到任何事件块**（没有 `START-OF-SELECTION` 之类）。
- 点「执行」按钮**什么都不会发生**。
- 但输入事务码进入，界面又能正常显示。

**推断的原因（待在系统内进一步验证）**

- 这类程序不是「自包含的可执行报表」（`REPORT ... ` 类型 1），而是**由事务码 + 屏幕驱动的程序**：逻辑挂在屏幕的 `PBO / PAI`（模块池）或由事务码的参数/入口直接调用其屏幕。
- `SE38` 的「执行」触发的是**报表事件**（`INITIALIZATION` → `START-OF-SELECTION` → …），既然没有事件块，自然无事发生；而事务码走的是**另一条入口**，直接调起屏幕，所以看起来「一切正常」。

**对本项目的启发**

- 要做带筛选界面的报表，老老实实用标准 `SELECTION-SCREEN` + `START-OF-SELECTION` 即可，**不必模仿**这种「无事件 + 事务码驱动」的写法。
- 想复用这类标准程序，只能 `CALL TRANSACTION`，不要指望当函数/子程序调用。

参考：[SAP Program RDDM0001](https://www.stechno.net/repository/sap-programs.html?id=RDDM0001)、[SE09 vs SE10 讨论](https://community.sap.com/t5/application-development-and-automation-discussions/se09-vs-se10/td-p/3564843)

## 8. 需求分析：一个用户名下有很多请求，怎么展示？

分析阶段用下面这张小表梳理「用户 → 对象 → 请求」的归属关系（同源文件：`开发传输变更交接清单.xlsx` → Sheet `交接程序逻辑分析`）：


| USER   | NAME    | TYPE   | REQ    |
| -------- | --------- | -------- | -------- |
| 202080 | ABC     | FUNC   | SKD001 |
| 202080 | BCS     | FUNC   | SKD001 |
| 202080 | LKJ     | REPO   |        |
| 202080 | LGA     | REPO   |        |
| 202080 | ZFI_LJH | BADI   |        |
| 202080 | ZDEMO   | DOMAIN |        |
| 202080 | ZT001   | TABLE  |        |
| 202080 | ZSSC    | STUC   |        |

三种可行的展示方案：


| 方案                             | 做法                                       | 优点                                              | 缺点                                             |
| ---------------------------------- | -------------------------------------------- | --------------------------------------------------- | -------------------------------------------------- |
| **A. 单层平铺 ALV（v0.1 采用）** | 请求 × 对象 一行一条                      | 实现最简单，排序 / 筛选 / 导出 / 小计全部白嫖 ALV | 同一请求重复多行，需要靠`TRKORR` 排序归组阅读    |
| **B. 层级 ALV**                  | `CL_SALV_TREE`：请求为父节点，对象为子节点 | 层次清晰，一个请求一行父节点                      | 不能直接用`CL_SALV_TABLE` 的工厂方法，代码量翻倍 |
| **C. 双 ALV 联动**               | 上：请求头；下：对象明细，双击联动         | 最接近标准事务码的观感                            | 两个容器、两次`factory`、事件处理最多            |

v0.1 先选 **A**：先把「查得全、查得对」做扎实，展示形式后面再升级。

## 9. 代码示例（v0.1）

```abap
*&---------------------------------------------------------------------*
*& Report ZTR_DEVELOPER_HANDOVER
*&---------------------------------------------------------------------*
REPORT ztr_developer_handover.

DATA lt_developer_handover TYPE TABLE OF ztr_developer_alv.
DATA ls_developer_handover TYPE ztr_developer_alv.
DATA lo_salv               TYPE REF TO cl_salv_table.

SELECT e070~trkorr,
       e070~as4user   AS truser,
       e070~as4date,
       e070~as4time,
       e07t~as4text,
       e071~pgmid,
       e071~object,
       e071~obj_name,
       e071~objfunc,
       tadir~devclass
  FROM e070
         INNER JOIN
           e071 ON e070~trkorr = e071~trkorr
             INNER JOIN
               tadir ON  e071~pgmid    = tadir~pgmid
                     AND e071~object   = tadir~object
                     AND e071~obj_name = tadir~obj_name
                 LEFT JOIN
                   e07t ON  e070~trkorr = e07t~trkorr
                        AND e07t~langu  = @sy-langu
  INTO TABLE @DATA(lt_e070)
  WHERE as4user = @sy-uname.

MOVE-CORRESPONDING lt_e070 TO lt_developer_handover.

TRY.
    cl_salv_table=>factory( IMPORTING r_salv_table = lo_salv
                            CHANGING  t_table      = lt_developer_handover ).
  CATCH cx_salv_msg.
ENDTRY.

lo_salv->get_columns( )->set_optimize( abap_true ).
lo_salv->get_functions( )->set_all( abap_true ).
lo_salv->get_display_settings( )->set_striped_pattern( abap_true ).
lo_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

lo_salv->display( ).
```

## 10. FAQ

**Q：SALV 怎么设置多选？**

```abap
" 只能选行（最常见的「多选」需求）
lo_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>multiple ).

" 行、列都可选（含单元格级选择，v0.1 用的是这个）
lo_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>row_column ).

" 单选 / 不可选
lo_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>single ).
lo_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>none ).
```

还要记得打开多选才用得到的两个开关，否则用户选了却「用不上」：

```abap
lo_salv->get_selections( )->set_selection_mode( if_salv_c_selection_mode=>multiple ).
lo_salv->get_functions( )->set_all( abap_true ).   " 工具条上的「全选/取消全选」
```

**Q：为什么 `MOVE-CORRESPONDING` 出来的字段是空的？**
字段名不一致。`MOVE-CORRESPONDING` 只搬运**同名**字段，不报错、不提示，所以 SELECT 别名、ALV 结构字段名、类型三者要对齐检查。

**Q：`AS4TEXT` 有时为空？**
`E07T` 是按语言存的，当前语言没有描述行就会为空。可按需放宽语言条件或给个占位符。

## 11. 路线图（v0.2+）

- [ ]  选择屏幕：用户（默认 `sy-uname`，支持多选 / 全部）、日期区间、包 `DEVCLASS`、对象类型
- [ ]  增加 `TRSTATUS`（请求状态）、`TRFUNCTION`（请求/任务/副本）列并支持筛选
- [ ]  `TADIR` / `E07T` 改 LEFT JOIN，保证对象与描述不丢行，并标注「无包 / 无描述」
- [ ]  展示形态升级：层级 ALV 或上下双 ALV 联动（方案 B / C）
- [ ]  一键导出 Excel、下载为交接清单附件，可选邮件发送
- [ ]  「按开发者 → 按包 → 按对象」的多视角汇总

## 12. 仓库结构

```text
ZTRH/
├── README.md                          # English（仓库入口，GitHub 落地页只认它）
├── README.cn.md                       # 中文（本文件）
├── ZTR_DEVELOPER_HANDOVER.prog.abap   # 程序源码
├── docs/
│   └── images/
│       └── design-preview.png
└── 开发传输变更交接清单.xlsx           # 需求/逻辑分析底稿（已在 .gitignore 中忽略）
```

> 后续若改用 abapGit 标准结构，建议把源码迁入 `src/`（`ztr_developer_handover.prog.abap`、`ztr_developer_alv.tabl.xml`）并补充 `.abapgit.xml`，同时把 `README.cn.md` 链接改成新路径。

## 13. 开发环境备注

在 macOS 上用 SAP GUI 写 ABAP 体验较差（编辑器、快捷键、粘贴都有损耗）。建议：

- 用 **abapGit** 把对象同步到本地，在 VS Code（`abapfs` / `abaplint`）里读写逻辑，回到系统只做激活与测试；
- 或者直接远程到 Windows 环境用完整版 SAP GUI.
