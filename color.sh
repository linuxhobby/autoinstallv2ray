#!/bin/bash

# 终端颜色定义
Font_Black="\033[30m"   # 黑色
Font_Red="\033[31m"     # 红色
Font_Green="\033[32m"   # 绿色
Font_Yellow="\033[33m"  # 黄色
Font_Blue="\033[34m"    # 蓝色
Font_Magenta="\033[35m" # 洋红色/紫色
Font_Cyan="\033[36m"    # 青色
Font_White="\033[37m"   # 白色
Font_Suffix="\033[0m"   # 重置颜色/颜色结尾

echo -e "--- 终端颜色样本展示 ---"
echo -e "${Font_Black}这是黑色样本 (Font_Black)${Font_Suffix}"
echo -e "${Font_Red}这是红色样本 (Font_Red)${Font_Suffix}"
echo -e "${Font_Green}这是绿色样本 (Font_Green)${Font_Suffix}"
echo -e "${Font_Yellow}这是黄色样本 (Font_Yellow)${Font_Suffix}"
echo -e "${Font_Blue}这是蓝色样本 (Font_Blue)${Font_Suffix}"
echo -e "${Font_Magenta}这是洋红色样本 (Font_Magenta)${Font_Suffix}"
echo -e "${Font_Cyan}这是青色样本 (Font_Cyan)${Font_Suffix}"
echo -e "${Font_White}这是白色样本 (Font_White)${Font_Suffix}"
echo -e "--- 展示结束 ---"