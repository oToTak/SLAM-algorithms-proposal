#!/bin/bash
# scripts/eval_all.sh

SUMMARY_FILE="results/summary.csv"

# Ініціалізація таблиці згідно з CONVENTIONS.md
echo "method,mode,dataset,seq,run,ate_rmse_m,rpe_trans_m,coverage,tracking_lost,commit" > $SUMMARY_FILE

# Прохід по всіх знайдених файлах траєкторій
for traj in results/*/*/*/*/traj_run*.txt; do
    # Перепустка, якщо файлів ще немає
    [ -e "$traj" ] || continue

    DIR=$(dirname "$traj")
    META="$DIR/meta.yaml"
    
    # TODO: Додати зчитування method, mode, dataset, seq з meta.yaml
    # TODO: Додати виклик evo_ape для розрахунку ate_rmse_m
    # Приклад: evo_ape tum <gt> "$traj" -as --t_max_diff 0.02 --save_results "$DIR/ape_run.zip"
    
    echo "Знайдено траєкторію: $traj. Очікується реалізація оцінки."
done

echo "Файл $SUMMARY_FILE оновлено."