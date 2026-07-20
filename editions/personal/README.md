# 北极星个人版

个人版面向单个用户，默认使用根目录唯一的共享 Harness。普通对话保持低摩擦；涉及文件写入、网络、外部发送、删除、采购、预算或业务系统变更时，仍按北极星协议确认。

## 使用

在仓库根目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\start-qianlima.ps1"
```

个人偏好必须可查看、编辑、禁用和删除。偏好只能调整交互与路由建议，不能改变权限、数据范围、审批要求或外部调用能力。

安装 Skill 时先经过共享 Skill Intake Gate；获批后仍需用户确认，并安装到受限目录。个人版不会复制企业组织、员工 RBAC 或企业审批配置。
