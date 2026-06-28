# 教员AI顾问

基于毛选思想的AI决策咨询系统。

## 快速开始

### 前置准备

1. 把毛选PDF放入 `data/` 文件夹，重命名为：
   - `maoxuan_vol1.pdf`（至少放第一卷）
   - `maoxuan_vol2.pdf`（可选）
   - `maoxuan_vol3.pdf`（可选）
   - `maoxuan_vol4.pdf`（可选）

### 一键部署

```bash
chmod +x setup.sh
./setup.sh
```

这个过程会自动安装所有依赖、下载AI模型、提取PDF文本、构建知识库。

### 启动使用

```bash
./start.sh
```

浏览器自动打开 `http://localhost:7860`。

## 手动分步执行（如果一键部署失败）

```bash
# 1. 安装依赖
brew install python
brew install --cask ollama
pip3 install PyMuPDF chromadb sentence-transformers gradio

# 2. 下载模型
ollama pull qwen2.5:7b

# 3. 提取PDF
python3 src/extract_pdf.py

# 4. 构建知识库
python3 src/build_knowledge.py

# 5. 启动
python3 src/chat_app.py
```

## 文件结构

```
jiaoyuan-ai/
├── data/               # 放毛选PDF
├── src/
│   ├── system_prompt.py    # 教员的核心Prompt（可编辑调整风格）
│   ├── extract_pdf.py      # PDF提取脚本
│   ├── build_knowledge.py  # 知识库构建脚本
│   └── chat_app.py         # 主程序（Gradio界面）
├── knowledge/          # 向量知识库（自动生成）
├── output/             # 生成的报告
├── setup.sh            # 一键部署
└── start.sh            # 启动脚本
```

## 调整教员风格

编辑 `src/system_prompt.py`，改完保存后刷新网页生效。

## 产品定位

不是"毛泽东聊天机器人"，而是**基于毛选决策方法论的AI战略顾问**。用户付费不是为了"和教员聊天"，而是为了**"让教员帮我分析问题"**——用矛盾分析法、阶段论、调查研究法找到破局路径。
