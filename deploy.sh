#!/bin/bash
set -e

# Flutter web ビルド（GitHub Pages 用の base-href を指定）
flutter build web --release --base-href /dqw_damage_calc/

# build/web の中身を docs フォルダにコピー
rm -rf docs
cp -r build/web docs

# Git コミットと push
git add docs
git commit -m "deploy"
git push
