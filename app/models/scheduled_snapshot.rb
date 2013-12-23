class ScheduledSnapshot < ActiveRecord::Base
  has_many :snapshot_summaries, dependent: :destroy
  belongs_to :user

  serialize :volume_id, Array
  serialize :time_of_day, Array
  serialize :day_of_week, Array
  serialize :month_of_year, Array
  serialize :tags, Hash

  after_initialize :default_values
  after_save :set_crontab, :check_scheduling_date
  
  scope :scheduled_today, lambda { where(start_date: Date.today)}
  scope :schedule_ended, lambda { where(end_date: Date.today-1)}

  REPEAT_TYPE = {"None" => 0, "Hourly" => 1, "Daily" => 2, "Weekly" => 3, "Monthly" => 4 }

  def frequency=(freq)
    self[:frequency] = REPEAT_TYPE[freq]
  end

  def end_date=(end_date)
    if frequency == "None"
      self[:end_date] = start_date
    else
      self[:end_date] = end_date
    end
  end

  def frequency
    REPEAT_TYPE.key(self[:frequency])
  end

  def set_crontab
    cron_array = case frequency
      when "None"
        [start_time.min, start_time.hour, start_date.mday, start_date.month, "*"]
      when "Hourly"
        ["0", time_of_day.join(','), "* * *"]
      when "Daily"
        [start_time.min, start_time.hour, "* *", day_of_week.join(',')]
      when "Weekly"
        [start_time.min, start_time.hour, "* *", start_date.wday]
      when "Monthly"
        [start_time.min, start_time.hour, start_date.mday, month_of_year.join(','), "*"]
    end
    update_column :cron, cron_array.join(" ")
  end
  
  def check_scheduling_date
    scheduled_date = self.start_date
    if (scheduled_date - Date.today) == 0
      Resque.set_schedule("scheduling_snapshot_#{self.id}", {
          :cron => self.cron,
          :class => "ScheduleSnapshot",
          :args => [self.user_id, self.id],
          :message => 'Schedule set',
          :persist => true
        })
    end
  end
  
  def default_values
    self.region = self.user.default_region
  end
end
