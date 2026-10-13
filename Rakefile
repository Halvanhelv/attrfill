# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative "config/application"

Rails.application.load_tasks

# TAILWIND=prebuilt: use the committed app/assets/builds/tailwind.css, for machines its binary cannot run on.
Rake::Task["tailwindcss:build"].clear_actions if ENV["TAILWIND"] == "prebuilt"
