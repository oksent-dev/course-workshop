namespace :demo do
  desc "Regenerate the original demo cover and charts from their sources"
  task illustrations: :environment do
    DemoIllustrations.generate!
  end

  desc "Create or update the two bundled demo courses without deleting other courses"
  task prepare: :environment do
    DemoCatalog.prepare!
    puts "Prepared Polish and English demo courses."
  end
end
