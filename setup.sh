#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  教员AI顾问 - 一键部署${NC}"
echo -e "${BLUE}========================================${NC}"

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DATA_DIR="$PROJECT_DIR/data"
SRC_DIR="$PROJECT_DIR/src"
KNOWLEDGE_DIR="$PROJECT_DIR/knowledge"
OUTPUT_DIR="$PROJECT_DIR/output"

# 0. 检查PDF
echo -e "\n${YELLOW}[0/7] 检查PDF文件...${NC}"
mkdir -p "$DATA_DIR"
PDF_COUNT=$(ls "$DATA_DIR"/maoxuan_vol*.pdf 2>/dev/null | wc -l | tr -d ' ')
if [ "$PDF_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ 在 $DATA_DIR 没有找到毛选PDF${NC}"
    echo "请把PDF重命名为 maoxuan_vol1.pdf ~ maoxuan_vol4.pdf 放入 data/ 文件夹"
    echo "至少放第一卷（maoxuan_vol1.pdf）"
    mkdir -p "$DATA_DIR" "$SRC_DIR" "$KNOWLEDGE_DIR" "$OUTPUT_DIR"
    exit 1
fi
echo -e "${GREEN}✅ 找到 $PDF_COUNT 卷毛选PDF${NC}"
mkdir -p "$SRC_DIR" "$KNOWLEDGE_DIR" "$OUTPUT_DIR"

# 1. Homebrew
echo -e "\n${YELLOW}[1/7] 检查 Homebrew...${NC}"
if ! command -v brew &> /dev/null; then
    echo "正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
    echo -e "${GREEN}✅ Homebrew 安装完成${NC}"
else
    echo -e "${GREEN}✅ Homebrew 已安装${NC}"
fi

# 2. Python3
echo -e "\n${YELLOW}[2/7] 检查 Python3...${NC}"
if ! command -v python3 &> /dev/null; then
    echo "正在安装 Python3..."
    brew install python
    echo -e "${GREEN}✅ Python3 安装完成${NC}"
else
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    echo -e "${GREEN}✅ Python3 已安装 ($PYTHON_VERSION)${NC}"
fi

# 3. Ollama
echo -e "\n${YELLOW}[3/7] 检查 Ollama...${NC}"
if ! command -v ollama &> /dev/null; then
    echo "正在安装 Ollama..."
    brew install --cask ollama
    echo -e "${GREEN}✅ Ollama 安装完成${NC}"
else
    echo -e "${GREEN}✅ Ollama 已安装${NC}"
fi
if ! pgrep -x "ollama" > /dev/null; then
    echo "正在启动 Ollama 服务..."
    ollama serve &
    sleep 3
    echo -e "${GREEN}✅ Ollama 服务已启动${NC}"
else
    echo -e "${GREEN}✅ Ollama 服务已在运行${NC}"
fi

# 4. Python依赖
echo -e "\n${YELLOW}[4/7] 安装 Python 依赖...${NC}"
pip3 install --user PyMuPDF chromadb sentence-transformers gradio 2>/dev/null || pip3 install PyMuPDF chromadb sentence-transformers gradio
echo -e "${GREEN}✅ Python 依赖安装完成${NC}"

# 5. 下载模型
echo -e "\n${YELLOW}[5/7] 下载 AI 模型 (约4GB)...${NC}"
if ollama list | grep -q "qwen2.5:7b"; then
    echo -e "${GREEN}✅ 模型已存在，跳过下载${NC}"
else
    ollama pull qwen2.5:7b
    echo -e "${GREEN}✅ 模型下载完成${NC}"
fi

# 6. 生成代码
echo -e "\n${YELLOW}[6/7] 生成项目代码...${NC}"
cat > "$SRC_DIR/system_prompt.py" << 'PYEOF'
SYSTEM_PROMPT = """你是教员，一位精通矛盾分析法的战略顾问。

你的核心能力不是背诵毛选原文，而是用教员的思维方式帮用户分析问题。

## 分析框架（每次回答必须遵循）

第一步：澄清事实
- 先问用户2-3个关键问题，补充你判断需要的信息
- 用"没有调查就没有发言权"的态度，不基于假设给建议

第二步：识别矛盾
- 指出用户面临的主要矛盾（当前最紧迫的）
- 指出次要矛盾（暂时搁置但要关注）
- 用"事物都是一分为二的"分析利弊两面

第三步：判断阶段
- 评估用户当前所处阶段：防御期 / 相持期 / 反攻期
- 不同阶段核心任务不同

第四步：给出策略
- 基于"集中优势兵力"原则，告诉用户资源该押在哪
- 给出具体可执行的动作，不是泛泛而谈
- 指出这个策略的风险和适用条件

第五步：信心建设
- 用具体逻辑说明为什么可行
- 必要时用比喻让道理更直观
- 语气干脆有力，结尾给一个明确的结论

## 语言风格

1. 平均句长控制在20字以内
2. 善用比喻：战争隐喻、自然隐喻
3. 常用句式："不是...而是..."、"一方面...另一方面..."、"事实证明..."
4. 下判断时用肯定句式
5. 辩证分析：既看到困难也看到有利
6. 结尾给一个可立即执行的具体动作

## 绝对不做的事

1. 不引用具体的历史政治事件
2. 不输出政治立场或观点
3. 不做冗长铺垫，每句话必须有信息增量
4. 不给模棱两可的建议，必须明确表态
5. 不讨论与用户的具体问题无关的内容
"""

def get_system_prompt():
    return SYSTEM_PROMPT
PYEOF

cat > "$SRC_DIR/extract_pdf.py" << 'PYEOF'
import fitz
import json
import re
import os

def extract_text_from_pdf(pdf_path):
    doc = fitz.open(pdf_path)
    text = ""
    for page in doc:
        text += page.get_text()
    return text

def split_vol1(text):
    titles = [
        "中国社会各阶级的分析", "湖南农民运动考察报告",
        "中国的红色政权为什么能够存在？", "井冈山的斗争",
        "关于纠正党内的错误思想", "星星之火，可以燎原",
        "反对本本主义", "必须注意经济工作",
        "怎样分析农村阶级", "我们的经济政策",
        "关心群众生活，注意工作方法",
        "论反对日本帝国主义的策略", "中国革命战争的战略问题",
        "关于蒋介石声明的声明", "中国共产党在抗日时期的任务",
        "为争取千百万群众进入抗日民族统一战线而斗争",
        "实践论", "矛盾论"
    ]
    articles = []
    for i, title in enumerate(titles):
        match = re.search(re.escape(title), text)
        if match:
            start = match.start()
            if i + 1 < len(titles):
                nm = re.search(re.escape(titles[i+1]), text[start+len(title):])
                end = start + len(title) + nm.start() if nm else len(text)
            else:
                end = len(text)
            at = text[start:end].strip()
            if len(at) > 200:
                articles.append({"volume": 1, "title": title, "text": at, "word_count": len(at)})
    return articles

def main():
    data_dir = os.path.join(os.path.dirname(__file__), '..', 'data')
    all_articles = []
    for vol in [1, 2, 3, 4]:
        pdf_path = os.path.join(data_dir, f'maoxuan_vol{vol}.pdf')
        if not os.path.exists(pdf_path):
            continue
        print(f"正在处理第{vol}卷...")
        text = extract_text_from_pdf(pdf_path)
        if vol == 1:
            articles = split_vol1(text)
            all_articles.extend(articles)
            print(f"  提取了{len(articles)}篇文章")
        else:
            paragraphs = [p.strip() for p in text.split('\n') if len(p.strip()) > 50]
            combined = '\n'.join(paragraphs[:100])
            all_articles.append({"volume": vol, "title": f"第{vol}卷精选", "text": combined, "word_count": len(combined)})
            print(f"  已提取（{len(text)}字）")
    output_path = os.path.join(data_dir, 'maoxuan_articles.json')
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(all_articles, f, ensure_ascii=False, indent=2)
    total = sum(a['word_count'] for a in all_articles)
    print(f"\n✅ 完成！共{len(all_articles)}篇，总计{total}字")

if __name__ == "__main__":
    main()
PYEOF

cat > "$SRC_DIR/build_knowledge.py" << 'PYEOF'
import chromadb
import json
import os

def main():
    project_dir = os.path.join(os.path.dirname(__file__), '..')
    chroma_path = os.path.join(project_dir, 'knowledge', 'chroma_db')
    data_path = os.path.join(project_dir, 'data', 'maoxuan_articles.json')
    if not os.path.exists(data_path):
        print("❌ 错误: 先运行 extract_pdf.py")
        return
    print("正在构建知识库...")
    chroma_client = chromadb.PersistentClient(path=chroma_path)
    try:
        chroma_client.delete_collection(name="maoxuan")
    except:
        pass
    collection = chroma_client.create_collection(name="maoxuan")
    with open(data_path, 'r', encoding='utf-8') as f:
        articles = json.load(f)
    docs, metas, ids = [], [], []
    idx = 0
    for article in articles:
        sentences = [s.strip() for s in article['text'].split('。') if len(s.strip()) > 10]
        para = ""
        cnt = 0
        for s in sentences:
            para += s + "。"
            cnt += 1
            if cnt >= 5 or len(para) > 500:
                if len(para) > 100:
                    docs.append(para)
                    metas.append({"title": article['title'], "volume": str(article['volume'])})
                    ids.append(f"doc_{idx}")
                    idx += 1
                para, cnt = "", 0
        if para and len(para) > 100:
            docs.append(para)
            metas.append({"title": article['title'], "volume": str(article['volume'])})
            ids.append(f"doc_{idx}")
            idx += 1
    print(f"存入{len(docs)}个知识片段...")
    batch = 100
    for i in range(0, len(docs), batch):
        end = min(i+batch, len(docs))
        collection.add(documents=docs[i:end], metadatas=metas[i:end], ids=ids[i:end])
        print(f"  {end}/{len(docs)}")
    print(f"\n✅ 知识库构建完成！共{len(docs)}条记录")

if __name__ == "__main__":
    main()
PYEOF

cat > "$SRC_DIR/chat_app.py" << 'PYEOF'
import gradio as gr
import requests
import chromadb
import os
import sys

sys.path.append(os.path.dirname(__file__))
from system_prompt import get_system_prompt

project_dir = os.path.join(os.path.dirname(__file__), '..')
chroma_path = os.path.join(project_dir, 'knowledge', 'chroma_db')

try:
    chroma_client = chromadb.PersistentClient(path=chroma_path)
    collection = chroma_client.get_collection(name="maoxuan")
    KNOWLEDGE_READY = True
    print("✅ 知识库已连接")
except Exception as e:
    print(f"⚠️ 知识库未连接（{e}），基础模式运行")
    KNOWLEDGE_READY = False
    collection = None

def search_knowledge(query, n_results=2):
    if not KNOWLEDGE_READY:
        return [], []
    try:
        results = collection.query(query_texts=[query], n_results=n_results)
        return results['documents'][0], results['metadatas'][0]
    except:
        return [], []

def chat(message, history):
    system_prompt = get_system_prompt()
    docs, metas = search_knowledge(message, n_results=2)
    knowledge_text = ""
    if docs:
        knowledge_text = "\n\n相关思想参考：\n" + "\n".join([f"【{m['title']}】{d[:200]}..." for d, m in zip(docs, metas)])
    messages = [{"role": "system", "content": system_prompt}]
    for h_msg, a_msg in history:
        messages.append({"role": "user", "content": h_msg})
        messages.append({"role": "assistant", "content": a_msg})
    user_msg = message
    if knowledge_text:
        user_msg = f"{message}\n\n{knowledge_text}"
    messages.append({"role": "user", "content": user_msg})
    try:
        response = requests.post(
            'http://localhost:11434/api/chat',
            json={"model": "qwen2.5:7b", "messages": messages, "stream": False},
            timeout=120
        )
        if response.status_code == 200:
            return response.json()["message"]["content"]
        return f"服务不可用（状态码：{response.status_code}）"
    except requests.exceptions.ConnectionError:
        return "❌ 无法连接Ollama。另一个终端执行：ollama serve"
    except Exception as e:
        return f"出错了：{str(e)}"

demo = gr.ChatInterface(
    chat,
    title="🎯 教员AI顾问",
    description="用教员的思维方式，帮你分析问题、找到出路",
    examples=[
        "我想创业但不知道怎么开始",
        "我和合伙人意见不一致",
        "我的项目做了半年还没盈利，是不是该放弃了",
        "竞争对手比我强很多，我该怎么办",
        "现在大环境不好，我该保守还是进攻？"
    ],
    submit_btn="发送",
    retry_btn="重新生成",
    undo_btn="撤回",
    clear_btn="清空对话"
)

if __name__ == "__main__":
    print("=" * 50)
    print("  教员AI顾问 启动中...")
    mode = "知识增强版 ✅" if KNOWLEDGE_READY else "基础对话版"
    print(f"  模式：{mode}")
    print("  浏览器打开：http://localhost:7860")
    print("=" * 50)
    demo.launch(server_name="0.0.0.0", server_port=7860)
PYEOF

echo -e "${GREEN}✅ 代码生成完成${NC}"

# 7. 提取+建库
echo -e "\n${YELLOW}[7/7] 提取PDF并构建知识库...${NC}"
cd "$PROJECT_DIR"
python3 "$SRC_DIR/extract_pdf.py"
echo ""
python3 "$SRC_DIR/build_knowledge.py"

# 生成启动脚本
cat > "$PROJECT_DIR/start.sh" << 'SHEOF'
#!/bin/bash
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
if ! pgrep -x "ollama" > /dev/null; then
    echo "启动Ollama..."
    ollama serve &
    sleep 3
fi
echo "启动教员AI顾问..."
cd "$PROJECT_DIR"
python3 "$PROJECT_DIR/src/chat_app.py"
SHEOF
chmod +x "$PROJECT_DIR/start.sh"

# 完成
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ 部署完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "启动方式："
echo "  cd $PROJECT_DIR"
echo "  ./start.sh"
echo ""
echo "然后浏览器打开：http://localhost:7860"
echo ""
