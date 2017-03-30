package com.example;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.rest.core.annotation.RepositoryRestResource;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.Id;
import java.util.stream.Stream;

@SpringBootApplication
public class HigginbothamServiceApplication {

	public static void main(String[] args) {
		SpringApplication.run(HigginbothamServiceApplication.class, args);
	}
}

@Component
class SampleDataCLR implements CommandLineRunner {

	private final PersonRepository personRepository;

	@Autowired
	public SampleDataCLR(PersonRepository personRepository) {
		this.personRepository = personRepository;
	}

	@Override
	public void run(String... args) throws Exception {
		Stream.of("Mark", "Dave", "Dean", "Bunn", "Sartori")
				.forEach(name -> personRepository.save(new Person(name)));
		personRepository.findAll().forEach(System.out::println);
	}
}

@RepositoryRestResource
interface PersonRepository extends JpaRepository<Person, Long> {

}

@Entity
class Person {

	@Id
	@GeneratedValue
	private Long id;

	private String name;

	public Person() {

	}

	public Person(String name) { this.name = name; }

	public Long getId() {
		return id;
	}

	public String getName() {
		return name;
	}

	@Override
	public String toString() {
		return "Person{" +
				"id=" + id +
				", name='" + name + '\'' +
				'}';
	}
}
