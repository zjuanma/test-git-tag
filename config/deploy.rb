require 'bundler/capistrano'
require 'capistrano-deploytags'

set :client, 'yomismo'
set :application, 'miaplicacion'
set :repository, "https://github.com/zjuanma/test-git-tag"
set :user, 'juanma'
set :deploy_to, "/home/juanma/app"
set :bundle_flags, '--deployment'

ssh_options[:config] = false
set :use_sudo, false
set :keep_releases, 5
set :rails_env, 'production'

set :scm, 'git'
# set :scm_verbose, true

ssh_options[:forward_agent] = true
# set :git_shallow_clone, 1

set :default_environment, {'LANG' => 'en_US.UTF-8'}

set :deploy_via, :export

# Resque variables not yet configurable in the resque-pool.yml file
# Warning, currently these values must be changed also in chef, as monit restarts resque-pool with fixed values
set :resque_verbosity, 1
set :resque_interval, 0.1

task :int do

  set :branch, 'integration'


  role :app, 'localhost', :jobs => true
  role :web, 'localhost'
  role :db,  'localhost', :primary => true

end

task :pre do

  set :branch, 'preproduction'

  role :app, 'localhost', :jobs => true
  role :web, 'localhost'
  role :db,  'localhost', :primary => true
end


url_root = 'test_url_root'
exclude_deployment_files = %w(crontab)
config_files = %w(database.yml)
dirs = %w(config)
after 'deploy:setup', 'deploy:create_dirs'
before 'deploy:finalize_update' do
  deploy.setup_deployment_files
  deploy.delete_html_dir
  deploy.symlink_config
  deploy.symlink_url_root
end

after  "deploy:prepare", "auto_tagger:create_ref"

after 'deploy',            'deploy:end'
after 'deploy:migrations', 'deploy:end'

after "deploy:end", "resque:restart"
after 'deploy:end', 'deploy:cleanup'
after "deploy:end", "auto_tagger:create_ref"
after "deploy:end", "auto_tagger:print_latest_refs"
#after 'deploy:end', 'newrelic:notice_deployment'


set :whenever_command, "bundle exec whenever"
#require "whenever/capistrano"

# Here comes the app config
namespace :deploy do

  desc "Upload code to remote integration/preproduction/production branch and deploy"
  task :upload do
    prepare
    default
  end

  desc "Prepare deploy uploading master/integration code to remote integration/preproduction/production branch"
  task :prepare do
    current_branch = run_locally 'git rev-parse --abbrev-ref HEAD'
    merge_branch = case branch
                     when 'integration'
                       'master'
                     when 'preproduction'
                       'integration'
                     when 'production'
                       'preproduction'
                    end
    run_locally "git checkout #{branch}; git pull origin #{branch}; git merge #{merge_branch}; git push origin #{branch}; git checkout #{current_branch}"
  end

  task :setup_deployment_files, :roles => :app do
    excludes = exclude_deployment_files.map{|f| "--exclude=#{f}" }.join(" ")
    run "rsync -avC #{excludes} #{release_path}/script/deploy/#{branch}/ #{release_path}"
  end

  task :symlink_config, :roles => :app do
    config_files.each do |f|
      run "ln -nfs #{shared_path}/config/#{f} #{release_path}/config/#{f}"
    end
  end

  task :symlink_url_root, :roles => :app do
    run "ln -nfs #{release_path}/public #{release_path}/public/#{url_root}"
  end

  task :restart, :roles => :app do
    run "touch #{current_path}/tmp/restart.txt"
  end

  task :create_dirs, :roles => :app do
    dirs.each do |d|
      run "mkdir -p #{shared_path}/#{d}"
    end
  end

  task :delete_html_dir, :roles => :app do
    run "rm -rf #{release_path}/app/assets/html"
  end

  desc 'Enables maintenance mode in the app'
  task :maintenance_on, :roles => :app do
    run "cp #{current_path}/public/maintenance.html.disabled #{shared_path}/system/maintenance.html"
  end

  desc 'Disables maintenance mode in the app'
  task :maintenance_off, :roles => :app do
    run "rm #{shared_path}/system/maintenance.html"
  end

  # Hook to launch dependent tasks after deployments
  task :end, :roles => :app do
  end
end

namespace :resque do

  desc "Starts resque-pool daemon."
  task :start, :roles => :app, :only => { :jobs => true } do
    run "cd #{latest_release} && RAILS_ENV=#{rails_env} INTERVAL=#{resque_interval} VERBOSE=#{resque_verbosity} bundle exec resque-pool -d -a #{application}"
  end

  desc "Sends INT to resque-pool daemon to close master, letting workers finish their jobs."
  task :stop, :roles => :app, :only => { :jobs => true }, :on_error => :continue do
    pid = "#{current_path}/tmp/pids/resque-pool.pid"
    run "kill -INT `cat #{pid}`"
  end

  desc "Restart resque workers"
  task :restart, :roles => :app, :only => { :jobs => true } do
    stop
    start
  end

  desc "List all resque processes."
  task :ps, :roles => :app, :only => { :jobs => true } do
    run 'ps -ef f | grep -E "[r]esque-(pool|[0-9])"'
  end

  desc "List all resque pool processes."
  task :psm, :roles => :app, :only => { :jobs => true } do
    run 'ps -ef f | grep -E "[r]esque-pool"'
  end

end

# Here comes the application namespace for custom tasks
namespace application do

end
