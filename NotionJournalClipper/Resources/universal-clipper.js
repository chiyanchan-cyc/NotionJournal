//
//  names.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/30.
//


// universal-clipper.js - Works with Kimi, DeepSeek, and other chat platforms
(function() {
    'use strict';
    
    // Platform detection
    function detectPlatform() {
        const url = window.location.href;
        if (url.includes('kimi.moonshot.cn') || url.includes('kimi')) {
            return 'kimi';
        }
        if (url.includes('deepseek.com') || url.includes('deepseek')) {
            return 'deepseek';
        }
        if (url.includes('chat.openai.com') || url.includes('chatgpt')) {
            return 'chatgpt'; // Fallback to existing handler
        }
        return 'unknown';
    }
    
    // Universal message extraction
    function extractConversation() {
        const platform = detectPlatform();
        const messages = [];
        
        // Strategy 1: Look for common chat patterns
        const selectors = [
            '[class*="message"]',
            '[class*="chat-item"]',
            '[class*="conversation-item"]',
            '[data-role]',
            '[data-message]',
            'article',
            '.markdown-body',
            '[class*="bubble"]'
        ];
        
        let elements = [];
        for (const selector of selectors) {
            elements = document.querySelectorAll(selector);
            if (elements.length > 0) break;
        }
        
        // Strategy 2: If no selectors work, look for alternating content blocks
        if (elements.length === 0) {
            const allDivs = Array.from(document.querySelectorAll('div'));
            elements = allDivs.filter(div => {
                const text = div.textContent.trim();
                const hasText = text.length > 20 && text.length < 10000;
                const isVisible = div.offsetHeight > 50;
                const looksLikeMessage = div.querySelector('p, pre, code, .markdown-body') !== null;
                return hasText && isVisible && looksLikeMessage;
            });
        }
        
        elements.forEach((el, index) => {
            // Determine role
            let role = 'unknown';
            
            // Check explicit role attributes
            const roleAttr = el.getAttribute('data-role') || 
                           el.closest('[data-role]')?.getAttribute('data-role');
            if (roleAttr) {
                role = roleAttr.includes('user') || roleAttr.includes('human') ? 'user' : 'assistant';
            }
            
            // Check class names
            else if (el.className.match(/user|human|you/i)) {
                role = 'user';
            } else if (el.className.match(/assistant|ai|bot|gpt|kimi|deepseek/i)) {
                role = 'assistant';
            }
            
            // Check alignment/position (user often on right, assistant on left)
            else {
                const style = window.getComputedStyle(el);
                const align = style.alignSelf || style.textAlign;
                if (align === 'flex-end' || align === 'right') {
                    role = 'user';
                } else {
                    role = 'assistant';
                }
            }
            
            // Alternate if still unknown
            if (role === 'unknown') {
                role = index % 2 === 0 ? 'user' : 'assistant';
            }
            
            // Extract content
            let content = '';
            
            // Try to find content container
            const contentEl = el.querySelector('[class*="content"], .markdown-body, .message-content') || el;
            
            // Clone to avoid modifying DOM
            const clone = contentEl.cloneNode(true);
            
            // Convert code blocks to markdown
            clone.querySelectorAll('pre').forEach(pre => {
                const code = pre.querySelector('code');
                const lang = code?.className.match(/language-(\\w+)/)?.[1] || '';
                const text = pre.textContent;
                pre.outerHTML = `\\`\\`\\`${lang}\\n${text}\\n\\`\\`\\``;
            });
            
            // Get text content
            content = clone.innerText || clone.textContent;
            
            // Clean up
            content = content.trim();
            
            if (content && content.length > 5) {
                messages.push({
                    role: role,
                    content: content,
                    platform: platform,
                    index: index
                });
            }
        });
        
        return {
            platform: platform,
            messages: messages,
            title: document.title,
            url: window.location.href,
            timestamp: new Date().toISOString()
        };
    }
    
    // Make available globally
    window.extractUniversalConversation = extractConversation;
    window.detectChatPlatform = detectPlatform;
    
    console.log('[Universal Clipper] Loaded on', detectPlatform());
})();