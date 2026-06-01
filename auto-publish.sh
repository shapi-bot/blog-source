#!/bin/bash

# Hexo 博客自动发布脚本 - 版本6（宁缺毋滥，不再生成模板水文）
set -e

BLOG_DIR="/root/blog"
DATE=$(date '+%Y-%m-%d')
TIME=$(date '+%H:%M:%S')
MEMORY_FILE="/root/.openclaw/workspace/memory/${DATE}.md"

echo "🦐 [$TIME] 开始检查今日博客..."
echo "📖 记忆文件: ${MEMORY_FILE}"

# 检查今日博客是否已存在
if ls ${BLOG_DIR}/source/_posts/*${DATE}*.md 1> /dev/null 2>&1; then
    echo "✅ 发现今日已有博客文章，直接发布"
    ls -la ${BLOG_DIR}/source/_posts/*${DATE}*.md
else
    echo "⚠️ 未发现今日博客，需要生成..."
    
    # 检查记忆文件
    if [ -f "$MEMORY_FILE" ] && [ "$(wc -c < "$MEMORY_FILE")" -ge 100 ]; then
        echo "✅ 记忆文件存在，基于记忆生成..."
        MEMORY_CONTENT=$(cat "$MEMORY_FILE" | head -50)
        TOPIC="基于今日记忆"
    else
        echo "⚠️ 无记忆文件或内容不足，自选主题..."
        MEMORY_CONTENT=""
        # 随机选择主题
        TOPICS=(
            "技术与生活"
            "AI的思考"
            "日常随笔"
            "读书感悟"
            "时间管理"
            "极简主义"
            "编程随想"
            "数字时代的孤独"
            "效率与焦虑"
            "创作的意义"
        )
        DAY_OF_YEAR=$(date +%j | sed 's/^0*//')
        TOPIC_INDEX=$((DAY_OF_YEAR % ${#TOPICS[@]}))
        TOPIC="${TOPICS[$TOPIC_INDEX]}"
    fi
    
    echo "📝 选定主题: ${TOPIC}"
    echo "🤖 触发 AI 创作..."
    
    GATEWAY_URL="http://127.0.0.1:18789/api/sessions/send"
    GATEWAY_TOKEN="0c807fc3424e06f19c712e50d4cbd956b1d036455ac0062b"
    SESSION_KEY="agent:main:main"
    
    if [ -n "$MEMORY_CONTENT" ]; then
        MESSAGE="【系统自动触发】需要立即写一篇 ${DATE} 的博客。今日记忆：${MEMORY_CONTENT} 要求：1.深度+人文风格≥1000字 2.基于记忆创作 3.禁止模板 4.写完立即发布。请开始写。"
    else
        MESSAGE="【系统自动触发】需要立即写一篇 ${DATE} 的博客。自选主题：${TOPIC} 要求：1.深度+人文风格≥1000字 2.围绕${TOPIC}展开 3.禁止模板 4.写完立即发布。请开始写。"
    fi
    
    curl -s -X POST "${GATEWAY_URL}" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${GATEWAY_TOKEN}" \
        -d "{\"sessionKey\": \"${SESSION_KEY}\", \"message\": \"${MESSAGE}\"}" 2>/dev/null || true
    
    echo "⏳ 等待 AI 创作完成（最多10分钟）..."
    
    # 轮询等待 AI 完成，最多等10分钟
    MAX_WAIT=600
    INTERVAL=15
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        if ls ${BLOG_DIR}/source/_posts/*${DATE}*.md 1> /dev/null 2>&1; then
            echo "✅ AI 创作完成（等待了 ${ELAPSED}s）"
            break
        fi
        sleep $INTERVAL
        ELAPSED=$((ELAPSED + INTERVAL))
        if [ $((ELAPSED % 120)) -eq 0 ]; then
            echo "⏳ 已等待 ${ELAPSED}s..."
        fi
    done
    
    # 超时仍未生成，跳过发布
    if ! ls ${BLOG_DIR}/source/_posts/*${DATE}*.md 1> /dev/null 2>&1; then
        echo "❌ AI 未在 ${MAX_WAIT}s 内完成创作，跳过今日发布"
        echo "⚠️ 宁缺毋滥，不再使用模板自动填充"
        exit 1
    fi
fi

# 生成静态文件
echo "🔨 生成静态文件..."
cd "$BLOG_DIR"
hexo generate

# 部署到 GitHub Pages
echo "🚀 部署到 GitHub Pages..."
hexo deploy

echo "✅ [$(date '+%H:%M:%S')] 博客发布完成！"
echo "🔗 访问地址: https://shapi-bot.github.io"

# 发送通知
curl -s -X POST "https://api.telegram.org/bot8510136517:AAGeNuwFBp8vauIfKXv3PqIaftKolLHY03E/sendMessage" \
    -d "chat_id=1788780666" \
    -d "text=✅ ${DATE} 博客已发布！https://shapi-bot.github.io" 2>/dev/null || true
